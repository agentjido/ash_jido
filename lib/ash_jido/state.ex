defmodule AshJido.State do
  @moduledoc """
  Uses an existing Ash resource row as the source of Agent state.

  Add `{AshJido.State, %{resource: Counter, update: :set_count}}` to the Agent's
  Plugins. Leave its Agent state schema empty. Use an unscoped resource with
  one primary key, an integer `:lock_version` attribute, and an update
  action with `change optimistic_lock(:lock_version)`. All writers must
  advance `:lock_version`.

  Read the row from `context.plugin_inputs[AshJido.State].runtime.row`.
  Return an `update/1` Directive to propose a write. Disable Jido persistence
  for Agents that write the row. Reads and updates use Ash authorization.
  Set `context.ash.actor` on the Turn when the resource requires an actor.
  """

  use Jido.Plugin

  alias Ash.Resource.Change.OptimisticLock
  alias Ash.Resource.Info
  alias AshJido.Error
  alias Jido.Joi

  defmodule Update do
    @moduledoc "Proposes one Ash row update in the current Turn."
    use Jido.Agent.Directive
    @enforce_keys [:attrs]
    defstruct [:attrs]

    @impl true
    def validate(%__MODULE__{attrs: attrs} = directive) when is_map(attrs) and not is_struct(attrs),
      do: {:ok, directive}

    def validate(_directive), do: {:error, :invalid_ash_state_changes}
  end

  @doc "Returns a Directive that proposes attributes for the admitted row."
  @spec update(map()) :: struct()
  def update(attrs) when is_map(attrs) and not is_struct(attrs), do: %Update{attrs: attrs}

  @impl Jido.Agent.Extension
  def normalize(%{resource: resource, update: action} = config)
      when is_atom(resource) and is_atom(action) and map_size(config) == 2 do
    with {:module, ^resource} <- Code.ensure_compiled(resource),
         true <- Info.resource?(resource),
         nil <- Info.multitenancy_strategy(resource),
         [key] when key != :lock_version <- Info.primary_key(resource),
         %{type: Ash.Type.Integer, allow_nil?: false} <- Info.attribute(resource, :lock_version),
         %{type: :update, manual?: false, changes: changes} <- Info.action(resource, action),
         true <- Enum.any?(changes, &optimistic_lock?/1) do
      {:ok, config}
    else
      _other -> {:error, :invalid_ash_state_resource}
    end
  end

  def normalize(_config), do: {:error, :invalid_ash_state_resource}

  defp optimistic_lock?(%{change: {OptimisticLock, [attribute: :lock_version]}, where: []}), do: true
  defp optimistic_lock?(_change), do: false

  @impl Jido.Agent.Extension
  def verify(_config, definition) do
    if definition.schema == Joi.object(%{}) and definition.initial_state == %{},
      do: :ok,
      else: {:error, :ash_state_schema_conflict}
  end

  @impl Jido.Plugin
  def state_spec(_opts), do: {:ash_changes, Joi.map() |> Joi.nullable() |> Joi.default(nil)}

  @impl Jido.Plugin
  def directives(_opts), do: [Update]

  @impl Jido.Plugin
  def admit(_runtime, admission, opts) do
    actor = get_in(admission.caller_context, [:ash, :actor])
    ash_opts = [actor: actor, authorize?: true]
    read_opts = Keyword.put(ash_opts, :not_found_error?, false)

    case Ash.get(Keyword.fetch!(opts, :resource), admission.agent_id, read_opts) do
      {:ok, %{lock_version: version} = row} when is_integer(version) -> {:ok, %{row: row, ash_opts: ash_opts}}
      {:ok, nil} -> {:error, :ash_state_not_found}
      {:ok, _row} -> {:error, :invalid_ash_state_lock_version}
      {:error, reason} -> {:error, Error.from_ash(reason)}
    end
  end

  @impl Jido.Plugin
  def reduce(reduction, _opts) do
    case for(%Update{attrs: attrs} <- reduction.directives, do: attrs) do
      [] -> {:ok, nil}
      [attrs] -> {:ok, attrs}
      _other -> {:error, :multiple_ash_state_updates}
    end
  end

  @impl Jido.Plugin
  def before_commit(_runtime, %{plugin_state: nil}, _opts), do: :ok

  def before_commit(_runtime, %{jido_persistence?: true}, _opts),
    do: {:error, :ash_state_requires_memory_turn}

  def before_commit(
        _runtime,
        %{plugin_state: attrs, runtime_input: %{row: %resource{} = row, ash_opts: ash_opts}},
        opts
      ) do
    protected = [:lock_version | Info.primary_key(resource)]

    if Enum.all?(Map.keys(attrs), &(is_atom(&1) and &1 not in protected)),
      do: save(row, attrs, Keyword.put(ash_opts, :action, Keyword.fetch!(opts, :update))),
      else: {:error, :invalid_ash_state_changes}
  end

  def before_commit(_runtime, _commit, _opts), do: {:error, :ash_state_not_admitted}

  defp save(row, attrs, opts) do
    case Ash.update(row, attrs, opts) do
      {:ok, _row} ->
        :ok

      {:error, %Ash.Error.Invalid{} = error} ->
        if Enum.any?(Error.extract_underlying_errors(error), &match?(%Ash.Error.Changes.StaleRecord{}, &1)),
          do: {:error, :stale_ash_state},
          else: {:error, Error.from_ash(error)}

      {:error, %Ash.Error.Forbidden{} = error} ->
        {:error, Error.from_ash(error)}

      {:error, _other} ->
        {:error, :indeterminate}
    end
  catch
    _kind, _reason -> {:error, :indeterminate}
  end
end
