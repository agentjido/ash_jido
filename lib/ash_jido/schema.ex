defmodule AshJido.Schema do
  @moduledoc false

  alias AshJido.TypeMapper
  alias Spark.Dsl.Transformer

  @default_belongs_to_type Application.compile_env(:ash, :default_belongs_to_type, :uuid)

  @doc false
  @spec build_parameter_schema(struct(), struct() | map(), Spark.Dsl.t()) :: Zoi.schema()
  def build_parameter_schema(ash_action, config, dsl_state) do
    build_input_schema(ash_action, config, {:dsl, dsl_state}, [])
  end

  @doc false
  @spec build_parameter_schema(module(), struct(), struct() | map(), keyword()) :: Zoi.schema()
  def build_parameter_schema(resource, ash_action, config, opts) when is_atom(resource) do
    build_input_schema(ash_action, config, {:resource, resource}, opts)
  end

  @doc false
  @spec build_output_schema(module() | Spark.Dsl.t(), struct(), atom(), struct() | map()) ::
          Zoi.schema()
  def build_output_schema(resource_or_dsl, ash_action, cardinality, config) do
    source = source(resource_or_dsl)

    result_schema =
      case ash_action.type do
        :destroy ->
          Zoi.object(%{
            destroyed?: Zoi.boolean(),
            identity: Zoi.map()
          })

        :action ->
          action_return_schema(ash_action)

        _other ->
          record = record_schema(source, config)

          case cardinality do
            :many -> Zoi.array(record)
            :one -> Zoi.nullable(record)
            :value -> Zoi.any()
          end
      end

    Zoi.object(
      %{
        result: result_schema,
        page: Zoi.nullable(page_schema()),
        metadata: Zoi.any() |> Zoi.nullable()
      },
      unrecognized_keys: :error
    )
  end

  @doc false
  @spec build_calculation_parameter_schema(module(), struct(), struct(), struct() | map()) ::
          Zoi.schema()
  def build_calculation_parameter_schema(resource, calculation, interface, config) do
    arguments = Map.new(calculation.arguments || [], &{&1.name, &1})
    attributes = resource |> Ash.Resource.Info.attributes() |> Map.new(&{&1.name, &1})

    fields =
      interface.args
      |> List.wrap()
      |> Enum.map(&normalize_calculation_input(&1, arguments, attributes))
      |> Enum.concat(
        Enum.map(interface.custom_inputs || [], fn input ->
          required? = input.allow_nil? == false and is_nil(input.default)
          {input.name, input_schema(input.type, input, input.name, config, required?)}
        end)
      )
      |> Enum.reject(fn {name, _schema} -> name in (interface.exclude_inputs || []) end)
      |> Map.new()

    Zoi.object(fields, unrecognized_keys: :error)
  end

  @doc false
  @spec build_value_output_schema(term(), keyword(), boolean()) :: Zoi.schema()
  def build_value_output_schema(type, constraints, allow_nil?) do
    result =
      TypeMapper.to_zoi!(type, %{constraints: constraints, allow_nil?: allow_nil?}, required?: true)

    Zoi.object(
      %{
        result: result,
        page: Zoi.null(),
        metadata: Zoi.any() |> Zoi.nullable()
      },
      unrecognized_keys: :error
    )
  end

  @doc false
  @spec primary_key_fields(Spark.Dsl.t() | module()) :: [atom()]
  def primary_key_fields(resource) when is_atom(resource) do
    Ash.Resource.Info.primary_key(resource)
  end

  def primary_key_fields(dsl_state) do
    dsl_state
    |> Transformer.get_entities([:attributes])
    |> Enum.filter(& &1.primary_key?)
    |> Enum.map(& &1.name)
  end

  @doc false
  @spec identity_fields(module(), atom() | [atom()] | false | nil) :: [atom()]
  def identity_fields(_resource, false), do: []
  def identity_fields(_resource, fields) when is_list(fields), do: fields

  def identity_fields(resource, identity) when is_atom(identity) and not is_nil(identity) do
    case Ash.Resource.Info.identity(resource, identity) do
      nil -> raise ArgumentError, "AshJido: identity #{inspect(identity)} does not exist on #{inspect(resource)}"
      definition -> definition.keys
    end
  end

  def identity_fields(resource, nil), do: primary_key_fields(resource)

  defp build_input_schema(ash_action, config, source, opts) do
    identity_fields = Keyword.get(opts, :identity_fields, default_identity_fields(ash_action, source, config))
    excluded_inputs = MapSet.new(Keyword.get(opts, :exclude_inputs, []))
    custom_inputs = Keyword.get(opts, :custom_inputs, [])

    fields =
      identity_field_schemas(source, identity_fields, ash_action.type, config) ++
        accepted_attribute_fields(ash_action, source, config) ++
        argument_fields(ash_action.arguments || [], config) ++
        custom_input_fields(custom_inputs, config)

    fields =
      fields
      |> Enum.reject(fn {name, _schema} -> MapSet.member?(excluded_inputs, name) end)
      |> select_action_parameters(config, identity_fields)
      |> add_query_fields(ash_action, config)

    fields
    |> Map.new()
    |> Zoi.object(unrecognized_keys: :error)
  end

  defp default_identity_fields(%{type: type}, source, config) when type in [:update, :destroy] do
    identity_fields_for_source(source, config_value(config, :identity))
  end

  defp default_identity_fields(_ash_action, _source, _config), do: []

  defp identity_fields_for_source({:resource, resource}, identity), do: identity_fields(resource, identity)
  defp identity_fields_for_source({:dsl, dsl_state}, nil), do: primary_key_fields(dsl_state)
  defp identity_fields_for_source({:dsl, _dsl_state}, false), do: []
  defp identity_fields_for_source({:dsl, _dsl_state}, fields) when is_list(fields), do: fields

  defp identity_fields_for_source({:dsl, _dsl_state}, identity) do
    raise ArgumentError,
          "AshJido: named identity #{inspect(identity)} is supported from a domain declaration"
  end

  defp accepted_attribute_fields(ash_action, source, config) do
    attributes = attributes_by_name(source)
    belongs_to = belongs_to_source_attributes(source)
    required = MapSet.new(Map.get(ash_action, :require_attributes, []) || [])

    Enum.flat_map(Map.get(ash_action, :accept, []) || [], fn name ->
      cond do
        attribute = Map.get(attributes, name) ->
          if include_input?(attribute, name, config) do
            required? =
              MapSet.member?(required, name) or
                (ash_action.type == :create and attribute.allow_nil? == false and
                   is_nil(attribute.default))

            [{name, input_schema(attribute.type, attribute, name, config, required?)}]
          else
            []
          end

        relationship = Map.get(belongs_to, name) ->
          if include_relationship_input?(relationship, name, config) do
            required? = MapSet.member?(required, name) or Map.get(relationship, :primary_key?, false)

            field = %{
              type: Map.get(relationship, :attribute_type) || @default_belongs_to_type,
              allow_nil?: Map.get(relationship, :allow_nil?, true),
              description: Map.get(relationship, :description),
              constraints: Map.get(relationship, :attribute_constraints, []) || []
            }

            [{name, input_schema(field.type, field, name, config, required?)}]
          else
            []
          end

        true ->
          []
      end
    end)
  end

  defp argument_fields(arguments, config) do
    arguments
    |> Enum.filter(&include_input?(&1, &1.name, config))
    |> Enum.map(fn argument ->
      required? = argument.allow_nil? == false and is_nil(argument.default)
      {argument.name, input_schema(argument.type, argument, argument.name, config, required?)}
    end)
  end

  defp custom_input_fields(custom_inputs, config) do
    custom_inputs
    |> Enum.filter(&include_input?(&1, &1.name, config))
    |> Enum.map(fn input ->
      required? = input.allow_nil? == false and is_nil(input.default)
      {input.name, input_schema(input.type, input, input.name, config, required?)}
    end)
  end

  defp identity_field_schemas(_source, [], _action_type, _config), do: []

  defp identity_field_schemas(source, identity_fields, action_type, config) do
    attributes = attributes_by_name(source)

    Enum.map(identity_fields, fn name ->
      schema =
        case Map.get(attributes, name) do
          nil -> Zoi.any()
          attribute -> input_schema(attribute.type, attribute, name, config, true)
        end

      description = "Identity field #{name} of the record to #{action_type}"
      {name, put_description(schema, description)}
    end)
  end

  defp input_schema(type, field, name, config, required?) do
    TypeMapper.to_zoi!(type, field,
      required?: required?,
      schema_override: Map.get(config_value(config, :schema_overrides, %{}) || %{}, name)
    )
  end

  defp select_action_parameters(fields, config, identity_fields) do
    case config_value(config, :action_parameters) do
      nil ->
        fields

      action_parameters ->
        allowed = MapSet.new(identity_fields ++ action_parameters)
        Enum.filter(fields, fn {name, _schema} -> MapSet.member?(allowed, name) end)
    end
  end

  defp add_query_fields(fields, %{type: :read}, config) do
    fields ++ Map.to_list(AshJido.QueryParams.schema(config))
  end

  defp add_query_fields(fields, _ash_action, _config), do: fields

  defp action_return_schema(action) do
    case Map.get(action, :returns) do
      nil -> Zoi.any()
      type -> TypeMapper.to_zoi!(type, %{constraints: Map.get(action, :constraints, []), allow_nil?: true})
    end
  end

  defp normalize_calculation_input({:optional, input}, arguments, attributes) do
    {name, schema} = normalize_calculation_input(input, arguments, attributes)
    {name, Zoi.optional(schema)}
  end

  defp normalize_calculation_input({:arg, name}, arguments, _attributes) do
    calculation_argument_schema!(name, arguments)
  end

  defp normalize_calculation_input({:ref, name}, _arguments, attributes) do
    calculation_reference_schema!(name, attributes)
  end

  defp normalize_calculation_input(:_record, _arguments, _attributes) do
    raise ArgumentError, "AshJido: calculation interfaces that require a record are not portable Actions"
  end

  defp normalize_calculation_input(name, arguments, attributes) when is_atom(name) do
    if Map.has_key?(arguments, name) do
      calculation_argument_schema!(name, arguments)
    else
      calculation_reference_schema!(name, attributes)
    end
  end

  defp calculation_argument_schema!(name, arguments) do
    case Map.get(arguments, name) do
      nil ->
        raise ArgumentError, "AshJido: calculation argument #{inspect(name)} does not exist"

      argument ->
        required? = argument.allow_nil? == false and is_nil(argument.default)
        {name, TypeMapper.to_zoi!(argument.type, argument, required?: required?)}
    end
  end

  defp calculation_reference_schema!(name, attributes) do
    case Map.get(attributes, name) do
      %{sensitive?: true} ->
        raise ArgumentError, "AshJido: calculation reference #{inspect(name)} is sensitive"

      nil ->
        raise ArgumentError, "AshJido: calculation reference #{inspect(name)} does not exist"

      attribute ->
        {name, TypeMapper.to_zoi!(attribute.type, attribute, required?: true)}
    end
  end

  defp record_schema(source, config) do
    attribute_fields =
      source
      |> attributes()
      |> Enum.filter(&(Map.get(&1, :public?, false) and not Map.get(&1, :sensitive?, false)))
      |> Map.new(fn attribute ->
        schema = TypeMapper.to_zoi!(attribute.type, attribute, required?: false)
        {attribute.name, schema}
      end)

    fields = Map.merge(attribute_fields, loaded_field_schemas(source, config))

    Zoi.object(fields, unrecognized_keys: :preserve)
  end

  defp loaded_field_schemas(source, config) do
    relationships = source |> relationships() |> public_by_name()
    calculations = source |> calculations() |> public_by_name()
    aggregates = source |> aggregates() |> public_by_name()

    config
    |> configured_loads()
    |> Enum.reduce(%{}, fn {name, nested}, fields ->
      cond do
        relationship = Map.get(relationships, name) ->
          destination = Map.get(relationship, :destination)
          nested_config = %{load: nested}
          related = record_schema({:resource, destination}, nested_config)

          schema =
            case Map.get(relationship, :cardinality) do
              :many -> Zoi.array(related)
              _other -> Zoi.nullable(related)
            end

          Map.put(fields, name, Zoi.optional(schema))

        calculation = Map.get(calculations, name) ->
          schema =
            TypeMapper.to_zoi!(calculation.type, calculation,
              required?: false,
              schema_override: Map.get(config_value(config, :schema_overrides, %{}) || %{}, name)
            )

          Map.put(fields, name, schema)

        aggregate = Map.get(aggregates, name) ->
          schema =
            TypeMapper.to_zoi!(aggregate.type, aggregate,
              required?: false,
              schema_override: Map.get(config_value(config, :schema_overrides, %{}) || %{}, name)
            )

          Map.put(fields, name, schema)

        true ->
          fields
      end
    end)
  end

  defp configured_loads(config) do
    [config_value(config, :load), config_value(config, :loads, [])]
    |> Enum.flat_map(&load_entries/1)
    |> Enum.reduce(%{}, fn {name, nested}, result ->
      Map.update(result, name, nested, &merge_nested_loads(&1, nested))
    end)
  end

  defp load_entries(nil), do: []
  defp load_entries(load) when is_atom(load), do: [{load, []}]

  defp load_entries(loads) when is_map(loads) and not is_struct(loads) do
    load_entries(Map.to_list(loads))
  end

  defp load_entries(loads) when is_list(loads) do
    Enum.flat_map(loads, fn
      {name, nested} when is_atom(name) -> [{name, nested}]
      name when is_atom(name) -> [{name, []}]
      _unsupported -> []
    end)
  end

  defp load_entries(_unsupported), do: []

  defp merge_nested_loads(left, right) do
    left_entries = load_entries(left)
    right_entries = load_entries(right)

    case left_entries ++ right_entries do
      [] -> []
      entries -> entries
    end
  end

  defp public_by_name(fields) do
    fields
    |> Enum.filter(&Map.get(&1, :public?, false))
    |> Map.new(&{&1.name, &1})
  end

  defp page_schema do
    Zoi.object(%{
      type: Zoi.enum([:offset, :keyset]),
      limit: Zoi.integer() |> Zoi.optional(),
      offset: Zoi.integer() |> Zoi.optional(),
      before: Zoi.string() |> Zoi.nullish(),
      after: Zoi.string() |> Zoi.nullish(),
      count: Zoi.integer() |> Zoi.nullish(),
      more?: Zoi.boolean()
    })
  end

  defp attributes_by_name(source), do: source |> attributes() |> Map.new(&{&1.name, &1})

  defp attributes({:resource, resource}), do: Ash.Resource.Info.attributes(resource)
  defp attributes({:dsl, dsl_state}), do: Transformer.get_entities(dsl_state, [:attributes])

  defp relationships({:resource, resource}), do: Ash.Resource.Info.relationships(resource)
  defp relationships({:dsl, dsl_state}), do: Transformer.get_entities(dsl_state, [:relationships])

  defp calculations({:resource, resource}), do: Ash.Resource.Info.calculations(resource)
  defp calculations({:dsl, dsl_state}), do: Transformer.get_entities(dsl_state, [:calculations])

  defp aggregates({:resource, resource}), do: Ash.Resource.Info.aggregates(resource)
  defp aggregates({:dsl, dsl_state}), do: Transformer.get_entities(dsl_state, [:aggregates])

  defp belongs_to_source_attributes(source) do
    source
    |> relationships()
    |> Enum.filter(&(&1.type == :belongs_to))
    |> Map.new(fn relationship ->
      {relationship.source_attribute || :"#{relationship.name}_id", relationship}
    end)
  end

  defp include_input?(input, name, config) do
    Map.get(input, :public?, true) or name in List.wrap(config_value(config, :private_inputs, []))
  end

  defp include_relationship_input?(relationship, name, config) do
    Map.get(relationship, :attribute_public?, true) or
      name in List.wrap(config_value(config, :private_inputs, []))
  end

  defp source(module) when is_atom(module), do: {:resource, module}
  defp source(dsl_state), do: {:dsl, dsl_state}

  defp config_value(config, key, default \\ nil) when is_map(config),
    do: Map.get(config, key, default)

  defp put_description(schema, description),
    do: %{schema | meta: %{schema.meta | description: description}}
end
