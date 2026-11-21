defmodule AshJido.State do
  @moduledoc """
  Runs one durable Jido Agent for an Ash resource row.

  Add this Plugin to the Agent and use its `ash` declaration in the
  Agent's state block. Configure the Jido instance with the AshJido
  checkpoint adapter and put both resources in the same database repo.
  The named update action must advance the row version with Ash optimistic
  locking.
  """

  use Jido.Plugin, imports: [AshJido.State.DSL]

  @behaviour Jido.Persistence.StateSource

  require Ash.Query
  require Logger

  alias Ash.Resource.Info
  alias AshJido.State.{Definition, Identity, Projection, Transaction}
  alias Jido.Persistence.Store

  @doc """
  Starts an Agent for an existing resource row.

  Use a scalar primary key or a map of primary key fields. Use the same
  partition and tenant to recover the stable address. All other options
  apply to Jido.start_agent/3.
  """
  @spec start_agent(module(), module(), term(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_agent(instance, module, key, opts \\ []) do
    if Keyword.keyword?(opts) and not Keyword.has_key?(opts, :state) do
      {row_opts, startup_opts} = Keyword.split(opts, [:tenant])
      Jido.start_agent(instance, module, Keyword.put(startup_opts, :state, AshJido.row(key, row_opts)))
    else
      startup_error(:ash_state_start_options, "Pass startup options as a keyword list and omit :state.")
    end
  end

  @doc "Returns the stable Jido address of a resource row."
  @spec address(module(), module(), term(), keyword()) :: {:ok, Jido.Agent.Address.t()} | {:error, term()}
  def address(instance, module, key, opts \\ []) do
    with {:ok, descriptor} <- descriptor(module),
         {:ok, id} <- startup_id(descriptor, {key, Keyword.take(opts, [:tenant])}),
         do: Jido.agent_address(instance, id, Keyword.take(opts, [:partition]))
  end

  @doc false
  @spec allow_direct_mutation(struct(), map()) :: :ok | {:error, :ash_state_direct_mutation}
  def allow_direct_mutation(%resource{} = row, %{agent_id: id, agent_module: module}) do
    with {:ok, %{resource: ^resource} = descriptor} <- descriptor(module),
         {:ok, key, tenant} <- Identity.decode(descriptor, id),
         {:ok, ^key} <- check_key(row, descriptor, key),
         :ok <- check_row_tenant(row, resource, tenant) do
      {:error, :ash_state_direct_mutation}
    else
      _other -> :ok
    end
  end

  def allow_direct_mutation(_row, _context), do: :ok

  defp descriptor(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__jido_state_provider__, 0) do
      case module.__jido_state_provider__() do
        {__MODULE__, descriptor, _schema} -> {:ok, descriptor}
        _ -> {:error, :ash_state_provider_required}
      end
    else
      {:error, :ash_state_provider_required}
    end
  end

  @impl true
  @doc false
  def state_source({resource, opts}, env), do: Definition.compile!(resource, opts, env)

  @impl true
  @doc false
  def startup_id(descriptor, {key, opts}) do
    with {:ok, tenant} <- startup_tenant(descriptor.resource, opts) do
      case Identity.encode(descriptor, key, tenant) do
        {:ok, id} ->
          {:ok, id}

        {:error, reason} ->
          fields = Enum.map_join(descriptor.key, ", ", &inspect/1)
          startup_error(reason, "Pass a valid Ash primary key. Expected fields #{fields}.")
      end
    end
  end

  def startup_id(_descriptor, _input) do
    startup_error(:ash_state_source_required, "Pass state: AshJido.row(primary_key) to start this Agent.")
  end

  defp startup_tenant(resource, opts) do
    if Keyword.keyword?(opts) and Keyword.keys(opts) in [[], [:tenant]] do
      case canonical_tenant(resource, opts[:tenant]) do
        {:ok, tenant} -> {:ok, tenant}
        {:error, reason} -> startup_error(reason, tenant_message(Info.multitenancy_strategy(resource)))
      end
    else
      startup_error(:ash_state_row_options, "AshJido.row/2 accepts only the :tenant option.")
    end
  end

  defp tenant_message(:attribute), do: "Pass a nonempty tenant string to AshJido.row/2."
  defp tenant_message(nil), do: "Omit :tenant for a resource without multitenancy."
  defp tenant_message(_strategy), do: "Ash-backed Agent state requires attribute multitenancy or an unscoped resource."

  defp startup_error(reason, message), do: Jido.Error.validation_result(reason, [:state], message)

  @impl true
  @doc false
  def open(descriptor, context, mode, agent, open) do
    result =
      with {:ok, transaction} <- Transaction.shared_repo(context.persistence, descriptor) do
        {repo, _, _} = transaction
        Transaction.run(transaction, fn -> open_row(descriptor, context, mode, agent, open, repo) end)
      end

    startup_result(result, mode, agent)
  end

  defp startup_result({:error, reason} = error, :create, %{state: nil}) do
    case reason do
      :ash_state_row_not_found ->
        startup_error(reason, "No accessible Ash row matched the primary key and tenant.")

      :ash_state_forbidden ->
        startup_error(reason, "The configured Ash actor cannot read this resource for Agent startup.")

      :ash_state_row_already_bound ->
        startup_error(reason, "Another Agent address already owns this Ash row.")

      :ash_state_requires_ash_persistence ->
        startup_error(reason, "Configure the Jido instance with AshJido.Persistence.Adapter.")

      :ash_state_requires_shared_transaction ->
        startup_error(reason, "Use the same SQLite or PostgreSQL repo for the Ash row and the Jido checkpoint.")

      _ ->
        error
    end
  end

  defp startup_result(result, _mode, _agent), do: result

  defp open_row(descriptor, context, :create, agent, open, repo) do
    with {:ok, row, _opts} <- read_for_agent(descriptor, context.address, nil, repo),
         {:ok, values} <- Projection.from_record(row, descriptor),
         :ok <- claim(context, agent.module, :create),
         do: open.(values)
  end

  defp open_row(descriptor, context, :restore, agent, open, repo) do
    with :ok <- claim(context, agent.module, :restore) do
      open.(fn saved, turn ->
        with {:ok, row, _opts} <- read_for_agent(descriptor, context.address, nil, repo),
             :ok <- same_generation(saved, row, descriptor),
             {:ok, values} <- Projection.from_record(row, descriptor) do
          if in_flight?(turn), do: {:ok, %{}}, else: {:ok, values}
        end
      end)
    end
  end

  defp in_flight?(nil), do: false
  defp in_flight?(%{status: status}), do: status not in [:completed, :failed, :cancelled]

  defp claim(%{persistence: %{store: store}, address: address}, module, mode) do
    key = "ash-jido/row-binding/v1/" <> :crypto.hash(:sha256, address.id)
    owner = :erlang.term_to_binary({address, module}, [:deterministic])

    case {Store.read(store, key), mode} do
      {{:ok, ^owner, _token}, _} -> :ok
      {{:ok, _owner, _token}, _} -> {:error, :ash_state_row_already_bound}
      {{:error, :not_found}, :create} -> Store.compare_and_swap(store, key, :not_found, owner)
      {{:error, :not_found}, :restore} -> {:error, :ash_state_binding_not_found}
      {{:error, _reason} = error, _} -> error
    end
  end

  @impl true
  @doc false
  def refresh(descriptor, context, agent) do
    with {:ok, {repo, _opts, _lock}} <- Transaction.shared_repo(context.persistence, descriptor),
         {:ok, row, _opts} <- read_for_agent(descriptor, context.address, nil, repo),
         :ok <- same_generation(agent, row, descriptor),
         do: Projection.from_record(row, descriptor)
  end

  @impl true
  @doc false
  def apply_state(descriptor, context, before, candidate, {repo, _transaction_opts, lock}) do
    with {:ok, changes, arguments} <- known(Projection.changes(before.state, candidate.state, descriptor)),
         {:ok, row, opts} <- known(read_for_agent(descriptor, context.address, lock, repo)),
         :ok <- known(same_generation(before, row, descriptor)),
         version = Map.fetch!(before.state, descriptor.version),
         :ok <- version_is(row, descriptor.version, version),
         {:ok, saved, notifications} <- write_row(row, changes, arguments, descriptor, opts, version, repo),
         :ok <- known(same_generation(before, saved, descriptor)),
         {:ok, values} <- known(Projection.from_record(saved, descriptor)),
         :ok <- known(Projection.verify_writable(candidate.state, values, descriptor)) do
      {:ok, values, after_commit(notifications)}
    end
  end

  defp write_row(row, changes, _arguments, _descriptor, _opts, _version, _repo) when map_size(changes) == 0,
    do: {:ok, row, []}

  defp write_row(row, changes, arguments, descriptor, opts, version, repo) do
    changeset = Ash.Changeset.for_update(row, descriptor.update, Map.merge(changes, arguments), opts)

    with :ok <- known(check_repo(changeset, repo)),
         :ok <- known(check_hooks(changeset)),
         changeset = Ash.Changeset.before_action(changeset, &guard_changeset(&1, repo)),
         update_opts = opts ++ [return_notifications?: true, atomic_upgrade?: false],
         {:ok, _updated, notifications} <- Ash.update(changeset, update_opts) |> ash_result(),
         {:ok, keys} <- known(project_key(row, descriptor)),
         {:ok, saved} <- known(read_row(descriptor, keys, opts, nil, repo)),
         :ok <- known(check_row_tenant(saved, descriptor.resource, opts[:tenant])),
         {:ok, ^keys} <- known(check_key(saved, descriptor, keys)),
         :ok <- version_is(saved, descriptor.version, version + 1) do
      {:ok, saved, notifications}
    end
  end

  defp project_key(row, descriptor) do
    keys = Map.take(row, descriptor.key)

    if map_size(keys) == length(descriptor.key) and
         Enum.all?(keys, fn {_, value} ->
           is_binary(value) or is_integer(value) or (is_atom(value) and not is_nil(value))
         end) do
      {:ok, keys}
    else
      {:error, :ash_state_key_unavailable}
    end
  end

  defp check_key(row, descriptor, keys) do
    case project_key(row, descriptor) do
      {:ok, ^keys} = match -> match
      _ -> {:error, :invalid_ash_state_identity}
    end
  end

  defp version_is(row, name, version) when is_integer(version) do
    if Map.fetch!(row, name) === version, do: :ok, else: {:error, {:rejected, :ash_state_stale_row}}
  end

  defp version_is(_row, _name, _version), do: {:error, {:rejected, :ash_state_version_unavailable}}

  defp read_for_agent(descriptor, address, lock, repo) do
    with {:ok, keys, tenant} <- Identity.decode(descriptor, address.id),
         {:ok, opts} <- ash_options(descriptor, address, keys, tenant),
         {:ok, row} <- read_row(descriptor, keys, opts, lock, repo),
         :ok <- check_row_tenant(row, descriptor.resource, tenant),
         {:ok, ^keys} <- check_key(row, descriptor, keys) do
      {:ok, row, opts}
    end
  end

  defp read_row(descriptor, keys, opts, lock, repo) do
    query =
      descriptor.resource
      |> Ash.Query.for_read(descriptor.read, %{}, opts)
      |> Ash.Query.filter(^keys)
      |> Ash.Query.load(descriptor.load)

    query = if lock, do: Ash.Query.lock(query, lock), else: query

    with :ok <- check_repo(query, repo),
         :ok <- check_hooks(query) do
      query = Ash.Query.before_action(query, &guard_query(&1, repo))

      case Ash.read_one(query, opts) do
        {:ok, %_{} = row} -> {:ok, row}
        {:ok, nil} -> {:error, :ash_state_row_not_found}
        {:error, error} -> {:error, ash_error(error)}
      end
    end
  end

  defp check_repo(%{context: %{data_layer: %{repo: override}}}, repo)
       when not is_nil(repo) and not is_nil(override) and override != repo,
       do: {:error, :ash_state_requires_shared_transaction}

  defp check_repo(_operation, _repo), do: :ok

  defp check_hooks(operation) do
    unsupported = [
      :after_action,
      :around_action,
      :atomic_after_action,
      :atomic_after_action_prepend,
      :before_transaction,
      :around_transaction,
      :after_transaction,
      :atomic_after_transaction,
      :atomic_after_transaction_prepend
    ]

    if Enum.any?(unsupported, &(Map.get(operation, &1, []) != [])) or
         Enum.any?(operation.before_action, &(not version_increment_hook?(&1))),
       do: {:error, :ash_state_unsupported_action_hooks},
       else: :ok
  end

  # Ash's optimistic_lock change registers its built-in increment as a before-action hook.
  defp version_increment_hook?(hook) when is_function(hook, 1),
    do: Function.info(hook, :module) == {:module, Ash.Resource.Change.Increment}

  defp version_increment_hook?(_hook), do: false

  defp guard_changeset(changeset, repo) do
    case check_repo(changeset, repo) do
      :ok -> changeset
      {:error, reason} -> {:error, boundary_error(reason)}
    end
  end

  defp guard_query(query, repo) do
    case check_repo(query, repo) do
      :ok -> query
      {:error, reason} -> Ash.Query.add_error(query, boundary_error(reason))
    end
  end

  defp boundary_error(reason) do
    Ash.Error.Changes.InvalidChanges.exception(
      validation: __MODULE__,
      value: reason,
      message: "AshJido requires the configured repo and a guarded state action."
    )
  end

  defp same_generation(%{state: state}, row, %{generation: field}) do
    case {Map.fetch(state, field), Map.fetch(row, field)} do
      {{:ok, generation}, {:ok, generation}} when is_binary(generation) -> :ok
      _ -> {:error, :ash_state_row_replaced}
    end
  end

  defp ash_options(descriptor, address, keys, tenant) do
    with {:ok, canonical} <- canonical_tenant(descriptor.resource, tenant),
         true <- canonical == tenant,
         {:ok, actor} <- actor(descriptor.actor, %{address: address, key: keys, tenant: tenant}) do
      {:ok, [actor: actor, tenant: tenant, authorize?: true]}
    else
      false -> {:error, :invalid_ash_state_tenant}
      {:error, _reason} = error -> error
    end
  end

  defp canonical_tenant(resource, tenant) do
    case {Info.multitenancy_strategy(resource), tenant} do
      {nil, nil} ->
        {:ok, nil}

      {:attribute, tenant} when is_binary(tenant) and byte_size(tenant) > 0 ->
        {module, function, args} = Info.multitenancy_tenant_from_attribute(resource)

        with {:ok, value} <- tenant_attribute(resource, tenant),
             canonical when is_binary(canonical) or is_integer(canonical) <- apply(module, function, [value | args]),
             token = to_string(canonical),
             true <- token != "",
             {:ok, ^value} <- tenant_attribute(resource, token) do
          {:ok, token}
        else
          _ -> {:error, :invalid_ash_state_tenant}
        end

      _ ->
        {:error, :invalid_ash_state_tenant}
    end
  rescue
    FunctionClauseError -> {:error, :invalid_ash_state_tenant}
    ArgumentError -> {:error, :invalid_ash_state_tenant}
  end

  defp tenant_attribute(resource, tenant) do
    {module, function, args} = Info.multitenancy_parse_attribute(resource)
    name = Info.multitenancy_attribute(resource)
    %{type: type, constraints: constraints} = Info.attribute(resource, name)

    with input when not is_nil(input) <- apply(module, function, [tenant | args]),
         {:ok, cast} <- Ash.Type.cast_input(type, input, constraints),
         {:ok, value} when not is_nil(value) <- Ash.Type.apply_constraints(type, cast, constraints) do
      {:ok, value}
    else
      _ -> {:error, :invalid_ash_state_tenant}
    end
  end

  defp check_row_tenant(_row, _resource, nil), do: :ok

  defp check_row_tenant(row, resource, tenant) do
    actual = Map.fetch!(row, Info.multitenancy_attribute(resource))

    case tenant_attribute(resource, tenant) do
      {:ok, ^actual} -> :ok
      _ -> {:error, :invalid_ash_state_tenant}
    end
  end

  defp actor(nil, _context), do: {:ok, nil}

  defp actor({module, function, args}, context) do
    case apply(module, function, [context | args]) do
      {:ok, actor} -> {:ok, actor}
      _ -> {:error, :ash_state_actor_unavailable}
    end
  end

  defp known({:error, reason}), do: {:error, {:rejected, reason}}
  defp known(result), do: result

  defp ash_result({:error, reason}), do: {:error, {:rejected, ash_error(reason)}}
  defp ash_result(result), do: result

  defp ash_error(%Ash.Error.Forbidden{}), do: :ash_state_forbidden

  defp ash_error(%Ash.Error.Invalid{errors: errors}) do
    Enum.find_value(errors, :ash_state_invalid_action, fn
      %Ash.Error.Changes.StaleRecord{} -> :ash_state_stale_row
      %Ash.Error.Changes.InvalidChanges{validation: __MODULE__, value: reason} -> reason
      _ -> nil
    end)
  end

  defp ash_error(_error), do: :ash_state_action_failed

  defp after_commit([]), do: nil
  defp after_commit(notifications), do: fn -> notify(notifications) end

  defp notify(notifications) do
    case Ash.Notifier.notify(notifications) do
      [] -> :ok
      _remaining -> Logger.warning("AshJido could not deliver all committed state notifications")
    end
  rescue
    _error -> Logger.warning("AshJido state notification failed after commit")
  catch
    _kind, _reason -> Logger.warning("AshJido state notification failed after commit")
  end
end
