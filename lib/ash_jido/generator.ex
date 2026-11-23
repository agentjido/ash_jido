defmodule AshJido.Generator do
  @moduledoc false

  alias AshJido.ActionDescriptor
  alias AshJido.Domain.Exposure
  alias AshJido.Resource.JidoAction
  alias Spark.Dsl.Transformer

  @unsafe_interface_options [:actor, :tenant, :authorize?, :domain, :scope, :tracer, :context]

  @doc false
  @spec compile_actions(Spark.Dsl.t(), [ActionDescriptor.t()], unique_names?: boolean()) ::
          {:ok, Spark.Dsl.t()}
  def compile_actions(dsl_state, descriptors, unique_names?: unique_names?) do
    owner = Transformer.get_persisted(dsl_state, :module)

    if unique_names?, do: validate_unique!(owner, descriptors, :name, "Jido Action name")
    validate_unique!(owner, descriptors, :module, "generated module")

    descriptors = Enum.map(descriptors, &compile_descriptor!/1)

    {:ok,
     dsl_state
     |> Transformer.persist(:generated_jido_modules, Enum.map(descriptors, & &1.module))
     |> Transformer.persist(:ash_jido_descriptors, descriptors)}
  end

  defp validate_unique!(owner, descriptors, key, label) do
    descriptors
    |> Enum.frequencies_by(&Map.fetch!(&1, key))
    |> Enum.each(fn
      {value, count} when count > 1 ->
        raise ArgumentError, "AshJido: duplicate #{label} #{inspect(value)} in #{inspect(owner)}"

      _entry ->
        :ok
    end)
  end

  @doc false
  @spec domain_action_descriptor(module(), JidoAction.t()) :: ActionDescriptor.t()
  def domain_action_descriptor(domain, %JidoAction{} = declaration) do
    unless is_atom(declaration.resource) and is_atom(declaration.ash_action) do
      raise ArgumentError,
            "AshJido: a domain action requires `action :name, Resource, :ash_action`"
    end

    config = %{
      declaration
      | action: declaration.ash_action,
        name: declaration.name || Atom.to_string(declaration.action)
    }

    resource = declaration.resource
    ash_action = Ash.Resource.Info.action(resource, declaration.ash_action)

    unless ash_action do
      raise ArgumentError,
            "AshJido: action #{inspect(declaration.ash_action)} was not found on #{inspect(resource)}"
    end

    validate_config!(resource, ash_action, config)

    build_action_descriptor(resource, ash_action, config, %{
      domain: domain,
      resource: resource,
      source: {:domain_action, domain, declaration.action},
      module: config.module_name || Module.concat([domain, "Jido", camelize(config.name)]),
      name: config.name,
      result_cardinality: result_cardinality(ash_action, nil),
      identity: action_identity_fields(resource, ash_action, config)
    })
  end

  @doc false
  @spec resource_action_descriptor(module(), JidoAction.t(), Spark.Dsl.t()) :: ActionDescriptor.t()
  def resource_action_descriptor(resource, config, dsl_state) do
    ash_action = get_dsl_action!(resource, config.action, dsl_state)
    domain = Ash.Resource.Info.domain(dsl_state)

    unless is_atom(domain) do
      raise ArgumentError,
            "AshJido: #{inspect(resource)}.#{ash_action.name} requires a compile-time Ash domain"
    end

    validate_config!(resource, ash_action, config)

    build_action_descriptor(dsl_state, ash_action, config, %{
      domain: domain,
      resource: resource,
      source: {:resource, resource, ash_action.name},
      module: config.module_name || Module.concat([resource, "Jido", camelize(ash_action.name)]),
      name: config.name || default_action_name(resource, ash_action),
      result_cardinality: result_cardinality(ash_action, nil),
      identity: action_identity_fields(dsl_state, ash_action, config)
    })
  end

  @doc false
  @spec interface_descriptor(
          module(),
          module(),
          Ash.Resource.Interface.t() | Ash.Resource.CalculationInterface.t(),
          Exposure.t()
        ) :: ActionDescriptor.t()
  def interface_descriptor(domain, resource, %Ash.Resource.Interface{} = interface, exposure) do
    ash_action = Ash.Resource.Info.action(resource, interface.action)

    unless ash_action do
      raise ArgumentError,
            "AshJido: interface #{inspect(interface.name)} refers to missing action " <>
              "#{inspect(resource)}.#{inspect(interface.action)}"
    end

    validate_default_options!(domain, interface)

    identity_fields = interface_identity_fields(resource, ash_action, interface, exposure)
    cardinality = result_cardinality(ash_action, interface)

    config =
      exposure
      |> Map.from_struct()
      |> Map.drop([:__spark_metadata__])
      |> Map.merge(%{
        interface: interface,
        custom_inputs: interface.custom_inputs || [],
        exclude_inputs: interface.exclude_inputs || [],
        default_options: interface.default_options || [],
        get?: interface.get? || Map.get(ash_action, :get?, false),
        get_by: identity_fields,
        not_found_error?: interface.not_found_error?
      })

    build_action_descriptor(
      resource,
      ash_action,
      config,
      %{
        domain: domain,
        resource: resource,
        source: {:code_interface, domain, interface.name},
        module: exposure.module_name || Module.concat([domain, "Jido", camelize(interface.name)]),
        name: exposure.name || Atom.to_string(interface.name),
        result_cardinality: cardinality,
        identity: identity_fields
      },
      identity_fields: interface_filter_fields(resource, interface),
      exclude_inputs: config.exclude_inputs,
      custom_inputs: config.custom_inputs
    )
  end

  def interface_descriptor(domain, resource, %Ash.Resource.CalculationInterface{} = interface, exposure) do
    calculation = Ash.Resource.Info.calculation(resource, interface.calculation)

    unless calculation do
      raise ArgumentError,
            "AshJido: calculation interface #{inspect(interface.name)} refers to missing calculation " <>
              "#{inspect(resource)}.#{inspect(interface.calculation)}"
    end

    config =
      exposure
      |> Map.from_struct()
      |> Map.drop([:__spark_metadata__])
      |> Map.merge(%{
        interface: interface,
        custom_inputs: interface.custom_inputs || [],
        exclude_inputs: interface.exclude_inputs || [],
        calculation_arguments: calculation_argument_names(calculation, interface),
        calculation_refs: calculation_reference_names(calculation, interface)
      })

    input_schema =
      AshJido.Schema.build_calculation_parameter_schema(resource, calculation, interface, config)

    output_schema =
      AshJido.Schema.build_value_output_schema(
        calculation.type,
        calculation.constraints,
        calculation.allow_nil?
      )

    module_name = exposure.module_name || Module.concat([domain, "Jido", camelize(interface.name)])

    attrs = %{
      id: "#{inspect(domain)}:#{inspect(resource)}:calculation:#{interface.name}",
      name: exposure.name || Atom.to_string(interface.name),
      module: module_name,
      domain: domain,
      resource: resource,
      ash_action: calculation.name,
      action_type: :calculation,
      source: {:calculation_interface, domain, interface.name},
      input_schema: input_schema,
      output_schema: output_schema,
      result_cardinality: :value,
      identity: [],
      select: nil,
      load: nil,
      config: config,
      primary_key: AshJido.Schema.primary_key_fields(resource)
    }

    ActionDescriptor.new!(attrs)
  end

  defp build_action_descriptor(schema_source, ash_action, config, attrs, input_options \\ []) do
    input_options = Keyword.put_new(input_options, :identity_fields, attrs.identity)
    id = "#{inspect(attrs.domain)}:#{inspect(attrs.resource)}:#{ash_action.name}:#{inspect(attrs.source)}"

    attrs
    |> Map.merge(%{
      id: id,
      ash_action: ash_action.name,
      action_type: ash_action.type,
      input_schema: AshJido.Schema.build_parameter_schema(schema_source, ash_action, config, input_options),
      output_schema: AshJido.Schema.build_output_schema(schema_source, ash_action, attrs.result_cardinality, config),
      select: config_value(config, :select),
      load: config_value(config, :load),
      config: config,
      primary_key: AshJido.Schema.primary_key_fields(attrs.resource)
    })
    |> ActionDescriptor.new!()
  end

  defp compile_descriptor!(%ActionDescriptor{module: module} = descriptor) do
    case Code.ensure_loaded(module) do
      {:module, ^module} -> replace_or_reject!(module, descriptor)
      {:error, _reason} -> emit_module!(descriptor)
    end
  end

  defp emit_module!(descriptor) do
    Code.compile_quoted(build_module_ast(descriptor))
    descriptor
  end

  defp build_module_ast(%ActionDescriptor{} = descriptor) do
    description =
      config_value(descriptor.config, :description) ||
        "Ash action #{inspect(descriptor.resource)}.#{descriptor.ash_action}"

    quote do
      defmodule unquote(descriptor.module) do
        @moduledoc "Generated Jido Action for `#{unquote(descriptor.resource)}.#{unquote(descriptor.ash_action)}`."

        use Jido.Action,
          name: unquote(descriptor.name),
          description: unquote(description),
          schema: unquote(Macro.escape(descriptor.input_schema)),
          output_schema: unquote(Macro.escape(descriptor.output_schema))

        @ash_jido_descriptor unquote(Macro.escape(descriptor))

        @doc "Returns the compile-time AshJido action descriptor."
        @spec __ash_jido__() :: AshJido.ActionDescriptor.t()
        def __ash_jido__, do: @ash_jido_descriptor

        @impl Jido.Action
        def on_before_validate_params(params),
          do: {:ok, AshJido.QueryParams.normalize_keys(params)}

        @impl Jido.Action
        def run(params, context),
          do: AshJido.Runtime.run(@ash_jido_descriptor, params, context)
      end
    end
  end

  defp replace_or_reject!(module, descriptor) do
    if function_exported?(module, :__ash_jido__, 0) do
      case module.__ash_jido__() do
        %ActionDescriptor{fingerprint: fingerprint} = existing when fingerprint == descriptor.fingerprint ->
          existing

        %ActionDescriptor{} ->
          :code.purge(module)
          :code.delete(module)
          emit_module!(descriptor)

        _other ->
          raise_module_collision!(module)
      end
    else
      raise_module_collision!(module)
    end
  end

  defp get_dsl_action!(resource, action_name, dsl_state) do
    dsl_state
    |> Transformer.get_entities([:actions])
    |> Enum.find(&(&1.name == action_name))
    |> case do
      nil ->
        available = dsl_state |> Transformer.get_entities([:actions]) |> Enum.map(& &1.name)

        raise ArgumentError,
              "AshJido: action #{inspect(action_name)} was not found on #{inspect(resource)}; " <>
                "available actions: #{inspect(available)}"

      action ->
        action
    end
  end

  defp interface_identity_fields(resource, ash_action, interface, exposure) do
    cond do
      not is_nil(exposure.identity) -> AshJido.Schema.identity_fields(resource, exposure.identity)
      interface.get_by_identity -> AshJido.Schema.identity_fields(resource, interface.get_by_identity)
      interface.get_by -> interface.get_by
      ash_action.type in [:update, :destroy] -> AshJido.Schema.primary_key_fields(resource)
      true -> []
    end
  end

  defp interface_filter_fields(resource, interface) do
    cond do
      interface.get_by_identity -> AshJido.Schema.identity_fields(resource, interface.get_by_identity)
      interface.get_by -> interface.get_by
      true -> []
    end
  end

  defp action_identity_fields(resource, %{type: type}, config)
       when is_atom(resource) and type in [:update, :destroy],
       do: AshJido.Schema.identity_fields(resource, config_value(config, :identity))

  defp action_identity_fields(dsl_state, %{type: type}, config) when type in [:update, :destroy] do
    case config_value(config, :identity) do
      nil -> AshJido.Schema.primary_key_fields(dsl_state)
      false -> []
      fields when is_list(fields) -> fields
      identity -> raise ArgumentError, "AshJido: use a domain declaration for named identity #{inspect(identity)}"
    end
  end

  defp action_identity_fields(_source, _action, _config), do: []

  defp result_cardinality(%{type: :read}, %{get?: true}), do: :one
  defp result_cardinality(%{type: :read, get?: true}, _interface), do: :one
  defp result_cardinality(%{type: :read}, _interface), do: :many
  defp result_cardinality(%{type: :action}, _interface), do: :value
  defp result_cardinality(_action, _interface), do: :one

  defp calculation_argument_names(calculation, interface) do
    arguments = MapSet.new(calculation.arguments || [], & &1.name)

    interface.args
    |> List.wrap()
    |> Enum.flat_map(fn
      {:arg, name} -> [name]
      {:optional, {:arg, name}} -> [name]
      {:optional, name} when is_atom(name) -> if MapSet.member?(arguments, name), do: [name], else: []
      name when is_atom(name) -> if MapSet.member?(arguments, name), do: [name], else: []
      _input -> []
    end)
  end

  defp calculation_reference_names(calculation, interface) do
    arguments = MapSet.new(calculation.arguments || [], & &1.name)

    interface.args
    |> List.wrap()
    |> Enum.flat_map(fn
      {:ref, name} -> [name]
      {:optional, {:ref, name}} -> [name]
      {:optional, name} when is_atom(name) -> if MapSet.member?(arguments, name), do: [], else: [name]
      name when is_atom(name) -> if MapSet.member?(arguments, name), do: [], else: [name]
      _input -> []
    end)
  end

  defp validate_default_options!(domain, interface) do
    options = interface.default_options

    if is_function(options) do
      raise ArgumentError,
            "AshJido: #{inspect(domain)}.#{interface.name} has dynamic default_options; " <>
              "generated Actions require static options"
    end

    case Enum.find(Keyword.keys(options || []), &(&1 in @unsafe_interface_options)) do
      nil -> :ok
      key -> raise ArgumentError, "AshJido: code interface default option #{inspect(key)} is not safe"
    end
  end

  defp validate_config!(resource, ash_action, config) do
    if ash_action.type != :read and
         Enum.any?([:filters, :sorts, :loads, :pagination], fn key ->
           value = config_value(config, key)
           not is_nil(value) and value != []
         end) do
      raise ArgumentError,
            "AshJido: query controls are only valid for read actions; " <>
              "#{inspect(resource)}.#{ash_action.name} is #{ash_action.type}"
    end
  end

  defp raise_module_collision!(module) do
    raise ArgumentError,
          "AshJido: generated module #{inspect(module)} collides with a module not owned by AshJido"
  end

  defp default_action_name(resource, ash_action) do
    resource_name = resource |> Module.split() |> List.last() |> Macro.underscore()

    case ash_action.type do
      :create -> "create_#{resource_name}"
      :read -> read_action_name(resource_name, ash_action.name)
      :update -> "update_#{resource_name}"
      :destroy -> "delete_#{resource_name}"
      :action -> "#{resource_name}_#{ash_action.name}"
    end
  end

  defp read_action_name(resource_name, :get), do: "get_#{resource_name}"
  defp read_action_name(resource_name, :read), do: "list_#{pluralize(resource_name)}"
  defp read_action_name(resource_name, :by_id), do: "get_#{resource_name}_by_id"
  defp read_action_name(resource_name, action), do: "#{resource_name}_#{action}"

  defp pluralize(word) do
    cond do
      String.ends_with?(word, "y") -> String.slice(word, 0..-2//1) <> "ies"
      String.ends_with?(word, ["s", "sh", "ch", "x", "z"]) -> word <> "es"
      true -> word <> "s"
    end
  end

  defp camelize(value), do: value |> to_string() |> Macro.camelize()
  defp config_value(config, key, default \\ nil), do: Map.get(config, key, default)
end
