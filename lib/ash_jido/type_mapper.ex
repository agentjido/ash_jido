defmodule AshJido.TypeMapper do
  @moduledoc false

  @doc false
  @spec to_zoi!(term(), map() | struct(), keyword()) :: Zoi.schema()
  def to_zoi!(ash_type, field_config \\ %{}, opts \\ []) do
    constraints = value(field_config, :constraints, []) || []

    ash_type
    |> base_schema(constraints, opts)
    |> apply_constraints(constraints)
    |> apply_description(value(field_config, :description))
    |> apply_presence(field_config, opts)
  end

  @doc false
  @spec typed_struct_to_schema(module()) :: Zoi.schema()
  def typed_struct_to_schema(module) when is_atom(module) do
    fields = module.subtype_constraints() |> Keyword.get(:fields, [])

    fields =
      Map.new(fields, fn {name, field_opts} ->
        field_config = Map.new(field_opts)
        {name, to_zoi!(field_config.type, field_config)}
      end)

    Zoi.object(fields)
  end

  @doc false
  @spec validate_uuid(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_uuid(value, _opts) when is_binary(value) do
    case Ash.Type.UUID.cast_input(value, []) do
      {:ok, _uuid} -> :ok
      _other -> {:error, "must be a UUID"}
    end
  end

  def validate_uuid(_value, _opts), do: {:error, "must be a UUID"}

  defp base_schema({:array, inner_type}, constraints, _opts) do
    item_constraints = Keyword.get(constraints, :items, [])

    item_schema =
      to_zoi!(inner_type, %{constraints: item_constraints, allow_nil?: false}, required?: true)

    Zoi.array(item_schema)
  end

  defp base_schema(ash_type, constraints, opts) do
    resolved = Ash.Type.get_type(ash_type)

    cond do
      Ash.Type.NewType.new_type?(resolved) ->
        subtype_constraints =
          if function_exported?(resolved, :subtype_constraints, 0),
            do: resolved.subtype_constraints(),
            else: []

        merged_constraints = Keyword.merge(subtype_constraints, constraints)

        resolved
        |> Ash.Type.NewType.subtype_of()
        |> base_schema(merged_constraints, opts)
        |> apply_constraints(merged_constraints)

      Spark.implements_behaviour?(resolved, Ash.Type.Enum) ->
        enum_schema(resolved)

      true ->
        built_in_schema(ash_type, resolved, constraints, opts)
    end
  end

  defp built_in_schema(ash_type, resolved, constraints, opts) do
    case resolved do
      Ash.Type.String -> Zoi.string()
      Ash.Type.Integer -> Zoi.integer()
      Ash.Type.Float -> Zoi.float()
      Ash.Type.Decimal -> Zoi.union([Zoi.number(), Zoi.string()])
      Ash.Type.Boolean -> Zoi.boolean()
      Ash.Type.UUID -> Zoi.string() |> Zoi.refine({__MODULE__, :validate_uuid, []})
      Ash.Type.Date -> Zoi.union([Zoi.date(), Zoi.string()])
      Ash.Type.DateTime -> Zoi.union([Zoi.datetime(), Zoi.string()])
      Ash.Type.UtcDatetime -> Zoi.union([Zoi.datetime(), Zoi.string()])
      Ash.Type.UtcDatetimeUsec -> Zoi.union([Zoi.datetime(), Zoi.string()])
      Ash.Type.NaiveDatetime -> Zoi.union([Zoi.datetime(), Zoi.string()])
      Ash.Type.Time -> Zoi.union([Zoi.time(), Zoi.string()])
      Ash.Type.Binary -> Zoi.string()
      Ash.Type.Atom -> atom_schema(constraints)
      Ash.Type.Map -> map_schema(constraints)
      Ash.Type.Struct -> struct_schema(constraints)
      Ash.Type.Union -> union_schema(constraints, opts)
      Ash.Type.Term -> Zoi.any()
      {:array, inner_type} -> base_schema({:array, inner_type}, constraints, opts)
      resolved -> custom_schema!(ash_type, resolved, opts)
    end
  end

  defp enum_schema(type) do
    values = type.values()
    Zoi.union([Zoi.enum(values), Zoi.enum(Enum.map(values, &to_string/1))])
  end

  defp atom_schema(constraints) do
    case Keyword.get(constraints, :one_of) do
      values when is_list(values) and values != [] ->
        strings = Enum.map(values, &to_string/1)
        Zoi.union([Zoi.enum(values), Zoi.enum(strings)])

      _other ->
        Zoi.union([Zoi.atom(), Zoi.string()])
    end
  end

  defp map_schema(constraints) do
    case Keyword.get(constraints, :fields) do
      fields when is_list(fields) and fields != [] ->
        fields =
          Map.new(fields, fn {name, field_opts} ->
            config = Map.new(field_opts)
            {name, to_zoi!(config.type, config)}
          end)

        Zoi.object(fields)

      _other ->
        Zoi.map()
    end
  end

  defp struct_schema(constraints) do
    case Keyword.get(constraints, :fields) do
      fields when is_list(fields) and fields != [] ->
        fields
        |> Map.new(fn {name, field_opts} ->
          field = Map.new(field_opts)
          {name, to_zoi!(field.type, field)}
        end)
        |> Zoi.object()

      _other ->
        case Keyword.get(constraints, :instance_of) do
          module when is_atom(module) -> embedded_resource_schema(module)
          _other -> Zoi.map()
        end
    end
  end

  defp embedded_resource_schema(module) do
    if Code.ensure_loaded?(module) and Ash.Resource.Info.resource?(module) do
      module
      |> Ash.Resource.Info.public_attributes()
      |> Enum.reject(& &1.sensitive?)
      |> Map.new(fn attribute ->
        {attribute.name, to_zoi!(attribute.type, attribute)}
      end)
      |> Zoi.object()
    else
      Zoi.map()
    end
  end

  defp union_schema(constraints, opts) do
    schemas =
      constraints
      |> Keyword.get(:types, [])
      |> Enum.map(fn {_name, config} ->
        base_schema(Keyword.fetch!(config, :type), Keyword.get(config, :constraints, []), opts)
      end)

    case schemas do
      [] -> custom_schema!(Ash.Type.Union, Ash.Type.Union, opts)
      schemas -> Zoi.union(schemas)
    end
  end

  defp custom_schema!(ash_type, resolved, opts) do
    case Keyword.get(opts, :schema_override) do
      nil ->
        raise ArgumentError,
              "AshJido does not support Ash type #{inspect(ash_type)} " <>
                "(resolved as #{inspect(resolved)}); provide an explicit Zoi schema override"

      schema ->
        schema
    end
  end

  defp apply_constraints(schema, constraints) do
    schema
    |> maybe_apply(:min_length, constraints, &Zoi.min/2)
    |> maybe_apply(:max_length, constraints, &Zoi.max/2)
    |> maybe_apply(:min, constraints, &Zoi.min/2)
    |> maybe_apply(:max, constraints, &Zoi.max/2)
    |> maybe_apply(:match, constraints, &Zoi.regex/2)
  end

  defp maybe_apply(schema, key, constraints, function) do
    case Keyword.fetch(constraints, key) do
      {:ok, value} -> function.(schema, value)
      :error -> schema
    end
  end

  defp apply_description(schema, description) when is_binary(description) do
    %{schema | meta: %{schema.meta | description: description}}
  end

  defp apply_description(schema, _description), do: schema

  defp apply_presence(schema, field_config, opts) do
    required? = Keyword.get(opts, :required?, required?(field_config))
    allow_nil? = value(field_config, :allow_nil?, true)
    default = value(field_config, :default)

    cond do
      not is_nil(default) and literal_default?(default) -> Zoi.default(schema, default)
      required? and allow_nil? -> Zoi.nullable(schema)
      required? -> schema
      allow_nil? -> Zoi.nullish(schema)
      true -> Zoi.optional(schema)
    end
  end

  defp required?(field_config) do
    value(field_config, :allow_nil?, true) == false and is_nil(value(field_config, :default))
  end

  defp literal_default?(default), do: not is_function(default) and not match?({_, _, _}, default)

  defp value(config, key, default \\ nil)
  defp value(config, key, default) when is_map(config), do: Map.get(config, key, default)
  defp value(config, key, default) when is_list(config), do: Keyword.get(config, key, default)
end
