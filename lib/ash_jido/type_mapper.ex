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
    |> maybe_add_required(field_config)
    |> maybe_add_doc(field_config)
    |> maybe_add_default(field_config)
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
end
