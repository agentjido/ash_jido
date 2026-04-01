defmodule AshJido.TypeMapper do
  @moduledoc false

  @doc """
  Converts an Ash type to a NimbleOptions schema entry.

  ## Examples

      iex> AshJido.TypeMapper.ash_type_to_nimble_options(Ash.Type.String, %{allow_nil?: false})
      [type: :string, required: true]

      iex> AshJido.TypeMapper.ash_type_to_nimble_options(Ash.Type.Integer, %{allow_nil?: true})
      [type: :integer]
  """
  def ash_type_to_nimble_options(ash_type, field_config \\ %{}) do
    base_type = map_ash_type(ash_type)

    [type: base_type]
    |> maybe_add_enum_constraint(field_config)
    |> maybe_add_required(field_config)
    |> maybe_add_doc(field_config)
    |> maybe_add_default(field_config)
  end

  @doc """
  Converts an Ash TypedStruct module to a NimbleOptions keyword list schema.

  This is useful for generating structured output schemas for LLM calls
  via ReqLLM.generate_object/4.

  ## Examples

      iex> AshJido.TypeMapper.typed_struct_to_schema(MyApp.PersonResult)
      [
        name: [type: :string, required: true, doc: "The person's name"],
        age: [type: :integer, doc: "The person's age"]
      ]
  """
  @spec typed_struct_to_schema(module()) :: keyword()
  def typed_struct_to_schema(module) when is_atom(module) do
    # Get field definitions from the TypedStruct's subtype_constraints
    constraints = module.subtype_constraints()
    fields = Keyword.get(constraints, :fields, [])

    Keyword.new(fields, fn {name, field_opts} ->
      field_config = Map.new(field_opts)
      opts = ash_type_to_nimble_options(field_config[:type], field_config)
      {name, opts}
    end)
  end

  @doc """
  Maps an Ash type to its corresponding NimbleOptions type.
  """
  def map_ash_type(ash_type) do
    case ash_type do
      Ash.Type.String -> :string
      Ash.Type.Integer -> :integer
      Ash.Type.Float -> :float
      Ash.Type.Decimal -> :float
      Ash.Type.Boolean -> :boolean
      Ash.Type.UUID -> :string
      Ash.Type.Date -> :string
      Ash.Type.DateTime -> :string
      Ash.Type.Time -> :string
      Ash.Type.Binary -> :string
      Ash.Type.Atom -> :atom
      Ash.Type.Map -> :map
      Ash.Type.Term -> :any
      {:array, inner_type} -> {:list, map_ash_type(inner_type)}
      _ -> :any
    end
  end

  defp maybe_add_required(options, field_config) do
    case field_config do
      %{allow_nil?: false} -> Keyword.put(options, :required, true)
      _ -> options
    end
  end

  defp maybe_add_doc(options, field_config) do
    case field_config do
      %{description: description} when is_binary(description) ->
        Keyword.put(options, :doc, description)

      _ ->
        options
    end
  end

  defp maybe_add_default(options, field_config) do
    case field_config do
      %{default: default} when not is_nil(default) ->
        Keyword.put(options, :default, default)

      _ ->
        options
    end
  end

  # Converts Ash.Type.Atom with one_of constraints to {:in, string_values}
  defp maybe_add_enum_constraint(opts, %{type: Ash.Type.Atom, constraints: constraints})
       when is_list(constraints) do
    case Keyword.get(constraints, :one_of) do
      values when is_list(values) and values != [] ->
        string_values = Enum.map(values, &to_string/1)
        Keyword.put(opts, :type, {:in, string_values})

      _ ->
        opts
    end
  end

  # Converts {:array, Ash.Type.Atom} with items one_of constraints to {:list, {:in, string_values}}
  defp maybe_add_enum_constraint(opts, %{type: {:array, Ash.Type.Atom}, constraints: constraints})
       when is_list(constraints) do
    items = Keyword.get(constraints, :items, [])

    case Keyword.get(items, :one_of) do
      values when is_list(values) and values != [] ->
        string_values = Enum.map(values, &to_string/1)
        Keyword.put(opts, :type, {:list, {:in, string_values}})

      _ ->
        opts
    end
  end

  defp maybe_add_enum_constraint(opts, _field_config), do: opts
end
