defmodule AshJido.Schema do
  @moduledoc false

  alias AshJido.TypeMapper
  alias Spark.Dsl.Transformer

  @doc false
  @spec build_parameter_schema(term(), AshJido.Resource.JidoAction.t(), Spark.Dsl.t()) ::
          keyword()
  def build_parameter_schema(ash_action, jido_action, dsl_state) do
    case ash_action.type do
      :create ->
        accepted_attrs =
          accepted_attributes_to_schema(ash_action, dsl_state, jido_action)

        action_args = action_args_to_schema(ash_action.arguments || [], jido_action)
        accepted_attrs ++ action_args

      :update ->
        base = primary_key_to_schema(dsl_state, :update)

        accepted_attrs =
          accepted_attributes_to_schema(ash_action, dsl_state, jido_action)

        action_args = action_args_to_schema(ash_action.arguments || [], jido_action)
        base ++ accepted_attrs ++ action_args

      :destroy ->
        base = primary_key_to_schema(dsl_state, :destroy)
        action_args = action_args_to_schema(ash_action.arguments || [], jido_action)
        base ++ action_args

      _ ->
        base_schema = action_args_to_schema(ash_action.arguments || [], jido_action)

        if ash_action.type == :read and jido_action.query_params? do
          base_schema ++ AshJido.QueryParams.schema(jido_action)
        else
          base_schema
        end
    end
  end

  @doc false
  @spec primary_key_fields(Spark.Dsl.t()) :: [atom()]
  def primary_key_fields(dsl_state) do
    dsl_state
    |> Transformer.get_entities([:attributes])
    |> Enum.filter(& &1.primary_key?)
    |> Enum.map(& &1.name)
  end

  defp accepted_attributes_to_schema(ash_action, dsl_state, jido_action) do
    accepted_names = ash_action.accept || []
    all_attributes = Transformer.get_entities(dsl_state, [:attributes])
    belongs_to_source_attributes = belongs_to_source_attributes(dsl_state)

    accepted_names
    |> Enum.flat_map(fn attr_name ->
      attr = Enum.find(all_attributes, &(&1.name == attr_name))
      relationship = Map.get(belongs_to_source_attributes, attr_name)

      cond do
        attr && include_schema_input?(attr, jido_action) ->
          [{attr_name, attribute_to_nimble_options(attr)}]

        attr ->
          []

        relationship && include_source_attribute_schema_input?(relationship, jido_action) ->
          [{attr_name, relationship_source_attribute_to_nimble_options(relationship)}]

        true ->
          []
      end
    end)
  end

  defp belongs_to_source_attributes(dsl_state) do
    dsl_state
    |> Transformer.get_entities([:relationships])
    |> Enum.filter(&(&1.type == :belongs_to))
    |> Map.new(fn relationship ->
      {relationship.source_attribute || :"#{relationship.name}_id", relationship}
    end)
  end

  defp primary_key_to_schema(dsl_state, action_type) do
    primary_key = primary_key_fields(dsl_state)
    all_attributes = Transformer.get_entities(dsl_state, [:attributes])

    Enum.map(primary_key, fn attr_name ->
      attr = Enum.find(all_attributes, &(&1.name == attr_name))

      opts =
        case attr do
          nil -> [type: :any]
          attr -> attribute_to_nimble_options(attr)
        end

      opts =
        opts
        |> Keyword.put(:required, true)
        |> Keyword.put(:doc, primary_key_doc(attr_name, action_type))

      {attr_name, opts}
    end)
  end

  defp primary_key_doc(attr_name, action_type) do
    action = action_type |> Atom.to_string() |> String.downcase()
    "Primary key field #{attr_name} of record to #{action}"
  end

  defp attribute_to_nimble_options(attr) do
    base_type = TypeMapper.map_ash_type(attr.type)

    opts = [type: base_type]

    opts =
      if attr.allow_nil? == false and is_nil(attr.default) do
        Keyword.put(opts, :required, true)
      else
        opts
      end

    case attr.description do
      desc when is_binary(desc) -> Keyword.put(opts, :doc, desc)
      _ -> opts
    end
  end

  defp relationship_source_attribute_to_nimble_options(relationship) do
    allow_nil? =
      if relationship.primary_key? do
        false
      else
        relationship.allow_nil?
      end

    TypeMapper.ash_type_to_nimble_options(
      relationship.attribute_type || Application.get_env(:ash, :default_belongs_to_type, :uuid),
      %{allow_nil?: allow_nil?}
    )
  end

  defp action_args_to_schema(arguments, jido_action) do
    arguments
    |> Enum.filter(&include_schema_input?(&1, jido_action))
    |> Enum.map(fn arg ->
      {arg.name, TypeMapper.ash_type_to_nimble_options(arg.type, arg)}
    end)
  end

  defp include_schema_input?(_input, %{include_private?: true}), do: true

  defp include_schema_input?(%{public?: false}, _jido_action), do: false
  defp include_schema_input?(_input, _jido_action), do: true

  defp include_source_attribute_schema_input?(_relationship, %{include_private?: true}), do: true

  defp include_source_attribute_schema_input?(%{attribute_public?: false}, _jido_action),
    do: false

  defp include_source_attribute_schema_input?(%{attribute_public?: true}, _jido_action), do: true

  defp include_source_attribute_schema_input?(relationship, jido_action),
    do: include_schema_input?(relationship, jido_action)
end
