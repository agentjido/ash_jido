defmodule AshJido.Agent.CompileActions do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias Ash.Resource.Builder
  alias AshJido.Agent.{Run, Schema}
  alias Jido.Agent.Route
  alias Spark.Dsl.Transformer

  @lifecycle [:start, :activate, :inspect, :status, :stop]
  @reserved @lifecycle ++ [:hibernate, :delete]
  @projection_keys [:id, :partition, :state_version]

  @impl true
  def transform(dsl) do
    resource = Transformer.get_persisted(dsl, :module)

    config =
      Map.new(
        [agent: nil, instance: nil, expose_lifecycle: [], expose_routes: [], expose_state: [], route_arguments: []],
        fn {key, default} -> {key, Transformer.get_option(dsl, [:jido_agent], key, default)} end
      )

    agent = config.agent

    with {:module, ^agent} <- Code.ensure_compiled(agent) do
      definition = Jido.Agent.definition(agent)
      validate!(dsl, config)
      routes = Enum.map(config.expose_routes, &compile_route!(&1, definition, config))
      fields = projection_fields!(definition, config.expose_state)
      operations = Enum.map(config.expose_lifecycle, &{&1, []}) ++ routes

      with {:ok, dsl} <- add_attributes(dsl, fields) do
        Enum.reduce_while(operations, {:ok, dsl}, fn {name, args}, {:ok, dsl} ->
          case add_action(dsl, name, args, resource, config) do
            {:ok, dsl} -> {:cont, {:ok, dsl}}
            {:error, _reason} = error -> {:halt, error}
          end
        end)
      end
    else
      _other -> raise ArgumentError, "AshJido.Agent could not load #{inspect(agent)}"
    end
  end

  defp validate!(dsl, config) do
    names = config.expose_lifecycle ++ config.expose_routes
    existing = Enum.map(Transformer.get_entities(dsl, [:actions]), & &1.name)

    unless Enum.uniq(names) == names and Enum.all?(names, &(&1 not in existing)) do
      raise ArgumentError, "AshJido.Agent has duplicate Ash action names"
    end

    unless Enum.all?(config.expose_lifecycle, &(&1 in @lifecycle)) do
      raise ArgumentError, "AshJido.Agent lifecycle operation has no supported Jido API"
    end

    unless Enum.all?(config.expose_routes, &(&1 not in @reserved)) do
      raise ArgumentError, "AshJido.Agent route uses a reserved lifecycle name"
    end

    overrides = Keyword.keys(config.route_arguments)

    unless Enum.uniq(overrides) == overrides and Enum.all?(overrides, &(&1 in config.expose_routes)) do
      raise ArgumentError, "AshJido.Agent argument overrides must name an exposed route once"
    end

    unless Enum.uniq(config.expose_state) == config.expose_state and
             Enum.all?(config.expose_state, &(&1 not in @projection_keys)) do
      raise ArgumentError, "AshJido.Agent has duplicate or reserved projection fields"
    end
  end

  defp compile_route!(name, definition, config) do
    with [route] <- Enum.filter(definition.routes, &(&1.as == name)),
         false <- Jido.Agent.Schema.wildcard?(route.path),
         true <- route.handler.kind in [:action, :flow],
         {:ok, [^route]} <- Route.matching(definition, route.path) do
      arguments = route_arguments!(name, route, config)

      if :address in Keyword.keys(arguments) do
        raise ArgumentError, "AshJido.Agent reserves the address argument"
      end

      {{:route, name, route.path, route.handler}, arguments}
    else
      _other -> raise ArgumentError, "AshJido.Agent route #{inspect(name)} must select one exact Action or Flow"
    end
  end

  defp route_arguments!(name, route, config) do
    case Keyword.fetch(config.route_arguments, name) do
      {:ok, arguments} ->
        arguments

      :error when route.handler.kind == :action ->
        Schema.fields!(route.handler.target.schema())

      :error ->
        raise ArgumentError, "AshJido.Agent Flow #{inspect(name)} requires explicit Ash arguments"
    end
  rescue
    error in ArgumentError ->
      raise ArgumentError, "AshJido.Agent route #{inspect(name)}: #{Exception.message(error)}"
  end

  defp projection_fields!(_definition, []), do: []

  defp projection_fields!(definition, names) do
    unless match?(%Zoi.Types.Map{fields: fields} when is_list(fields), definition.schema) do
      raise ArgumentError, "AshJido.Agent requires an object schema for state projection"
    end

    Enum.map(names, fn name ->
      case Keyword.fetch(definition.schema.fields, name) do
        {:ok, schema} -> {name, Schema.field!(schema)}
        :error -> raise ArgumentError, "AshJido.Agent state field #{inspect(name)} is not in the Agent schema"
      end
    end)
  end

  defp add_attributes(dsl, fields) do
    attrs = [
      id: [type: :string, primary_key?: true, allow_nil?: false],
      partition: [type: :string],
      state_version: [type: :integer, allow_nil?: false]
    ]

    Enum.reduce_while(attrs ++ fields, {:ok, dsl}, fn {name, options}, {:ok, dsl} ->
      if Ash.Resource.Info.attribute(dsl, name) do
        raise ArgumentError, "AshJido.Agent projection attribute #{inspect(name)} already exists"
      end

      {type, options} = Keyword.pop!(options, :type)

      case Builder.add_new_attribute(dsl, name, type, [public?: true, writable?: false] ++ options) do
        {:ok, dsl} -> {:cont, {:ok, dsl}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp add_action(dsl, operation, arguments, resource, config) do
    name = action_name(operation)
    arguments = [address: [type: :term, allow_nil?: false]] ++ arguments

    options = [
      public?: true,
      run: {Run, operation: operation, agent: config.agent, instance: config.instance, fields: config.expose_state},
      arguments: Enum.map(arguments, &build_argument!/1)
    ]

    options =
      if operation == :inspect,
        do: [returns: :struct, constraints: [instance_of: resource]] ++ options,
        else: [returns: :map] ++ options

    Builder.add_action(dsl, :action, name, options)
  end

  defp build_argument!({name, options}) do
    {type, options} = Keyword.pop!(options, :type)
    {:ok, argument} = Builder.build_action_argument(name, type, options)
    argument
  end

  defp action_name({:route, name, _path, _handler}), do: name
  defp action_name(name), do: name

  @impl true
  def before?(Ash.Resource.Transformers.CachePrimaryKey), do: true
  def before?(_transformer), do: false
end
