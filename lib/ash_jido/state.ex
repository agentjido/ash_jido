defmodule AshJido.State do
  @moduledoc """
  Runs one durable Jido Agent for an Ash resource row.

  Import the declaration from AshJido.State.DSL. Configure the Jido instance
  with the AshJido checkpoint adapter and place both resources in the same
  database repo. The named update action must advance the row version with
  Ash optimistic locking.
  """

  @behaviour Jido.AgentServer.StateProvider

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
    {tenant, opts} = Keyword.pop(opts, :tenant)

    with {:ok, descriptor} <- descriptor(module),
         {:ok, config} <- Jido.Persistence.resolve_agent_config(:inherit, instance),
         {:ok, _transaction} <- Transaction.shared_repo(config, descriptor),
         {:ok, id} <- Identity.encode(descriptor, key, tenant),
         {:ok, address} <- Jido.agent_address(instance, id, Keyword.take(opts, [:partition])),
         {:ok, row, _ash_opts} <- read_for_agent(descriptor, address, nil),
         {:ok, state} <- Projection.from_record(row, descriptor),
         {:ok, agent} <- module.instantiate(id: id, state: state),
         {:ok, server} <- Jido.start_agent(instance, agent, opts),
         :ok <- Jido.AgentServer.await_ready(server, Keyword.get(opts, :persistence_timeout, 5_000)) do
      {:ok, server}
    end
  end

  @doc "Returns the stable Jido address of a resource row."
  @spec address(module(), module(), term(), keyword()) :: {:ok, Jido.Agent.Address.t()} | {:error, term()}
  def address(instance, module, key, opts \\ []) do
    with {:ok, descriptor} <- descriptor(module),
         {:ok, id} <- Identity.encode(descriptor, key, Keyword.get(opts, :tenant)),
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
  def compile_state!({resource, opts}, env), do: Definition.compile!(resource, opts, env)

  @impl true
  @doc false
  def open(descriptor, context, mode, agent, open) do
    with {:ok, transaction} <- Transaction.shared_repo(context.persistence, descriptor) do
      Transaction.run(transaction, fn -> open_row(descriptor, context, mode, agent, open) end)
    end
  end

  defp open_row(descriptor, context, :create, agent, open) do
    with {:ok, agent} <- refresh(descriptor, context, agent),
         :ok <- claim(context, agent.module, :create),
         do: open.(agent)
  end

  defp open_row(descriptor, context, :restore, agent, open) do
    with :ok <- claim(context, agent.module, :restore),
         {:ok, saved, revision, agent_revision, turn, handoffs} <- open.(agent),
         {:ok, refreshed} <- refresh(descriptor, context, saved) do
      current = if in_flight?(turn), do: saved, else: refreshed
      {:ok, current, revision, agent_revision, turn, handoffs}
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
    with {:ok, row, _opts} <- read_for_agent(descriptor, context.address, nil),
         do: merge_projection(agent, row, descriptor)
  end

  @impl true
  @doc false
  def commit(descriptor, context, before, candidate, save) do
    with {:ok, transaction} <- Transaction.shared_repo(context.persistence, descriptor),
         {:ok, changes, arguments} <- known(Projection.changes(before.state, candidate.state, descriptor)),
         {:ok, payload, notifications} <-
           Transaction.run(transaction, fn ->
             commit_row(descriptor, context, transaction, before, candidate, changes, arguments, save)
           end) do
      notify(notifications)
      {:ok, payload}
    end
  end

  defp commit_row(descriptor, context, {repo, _transaction_opts, lock}, before, candidate, changes, arguments, save) do
    with {:ok, row, opts} <- known(read_for_agent(descriptor, context.address, lock, repo)),
         version = Map.fetch!(before.state, descriptor.version),
         :ok <- version_is(row, descriptor.version, version),
         {:ok, saved, notifications} <- write_row(row, changes, arguments, descriptor, opts, version, repo),
         {:ok, canonical} <- known(merge_projection(candidate, saved, descriptor)),
         {:ok, payload} <- save.(canonical) do
      {:ok, payload, notifications}
    end
  end

  defp write_row(row, changes, _arguments, _descriptor, _opts, _version, _repo) when map_size(changes) == 0,
    do: {:ok, row, []}

  defp write_row(row, changes, arguments, descriptor, opts, version, repo) do
    changeset = Ash.Changeset.for_update(row, descriptor.update, Map.merge(changes, arguments), opts)

    with :ok <- known(check_repo(changeset, repo)),
         {:ok, _updated, notifications} <-
           Ash.update(changeset, Keyword.put(opts, :return_notifications?, true)) |> ash_result(),
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

  defp read_for_agent(descriptor, address, lock, repo \\ nil) do
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

    with :ok <- check_repo(query, repo) do
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

  defp merge_projection(agent, row, descriptor) do
    with {:ok, values} <- Projection.from_record(row, descriptor),
         {:ok, current} <- Jido.Agent.set(agent, values) do
      {:ok, current}
    else
      {:error, %_{} = _error} -> {:error, :invalid_ash_state_projection}
      {:error, _reason} = error -> error
    end
  end

  defp ash_options(descriptor, address, keys, tenant) do
    with :ok <- validate_tenant(descriptor.resource, tenant),
         {:ok, actor} <- actor(descriptor.actor, %{address: address, key: keys, tenant: tenant}) do
      {:ok, [actor: actor, tenant: tenant, authorize?: true]}
    end
  end

  defp validate_tenant(resource, tenant) do
    case {Info.multitenancy_strategy(resource), tenant} do
      {nil, nil} -> :ok
      {:attribute, tenant} when is_binary(tenant) and byte_size(tenant) > 0 -> :ok
      _ -> {:error, :invalid_ash_state_tenant}
    end
  end

  defp check_row_tenant(_row, _resource, nil), do: :ok

  defp check_row_tenant(row, resource, tenant) do
    actual = Map.fetch!(row, Info.multitenancy_attribute(resource))

    if (is_binary(actual) or is_integer(actual)) and to_string(actual) == tenant,
      do: :ok,
      else: {:error, :invalid_ash_state_tenant}
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
    if Enum.any?(errors, &match?(%Ash.Error.Changes.StaleRecord{}, &1)),
      do: :ash_state_stale_row,
      else: :ash_state_invalid_action
  end

  defp ash_error(_error), do: :ash_state_action_failed

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
