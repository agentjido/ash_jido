defmodule AshJido.Mapper do
  @moduledoc false

  @ash_meta_keys [
    :__meta__,
    :__metadata__,
    :aggregates,
    :calculations,
    :__order__,
    :__lateral_join_source__
  ]

  @doc """
  Wraps an Ash result according to the Jido action configuration.

  Handles both wrapped results ({:ok, data}, {:error, error}) and raw data
  returned directly from Ash operations (lists, structs, atoms).

  ## Ash Operation Return Values

  - Create: {:ok, result} - Already wrapped
  - Update: {:ok, result} - Already wrapped
  - Read: [record1, record2, ...] - Raw list, needs wrapping
  - Destroy: :ok - Raw atom, needs wrapping

  ## Examples

      iex> AshJido.Mapper.wrap_result({:ok, %User{id: 1, name: "John"}}, %{output_map?: true})
      {:ok, %{id: 1, name: "John"}}

      iex> AshJido.Mapper.wrap_result([%User{id: 1}, %User{id: 2}], %{output_map?: true})
      {:ok, [%{id: 1}, %{id: 2}]}

      iex> AshJido.Mapper.wrap_result(:ok, %{})
      {:ok, %{deleted: true}}

      iex> AshJido.Mapper.wrap_result({:error, %Ash.Error.Invalid{}}, %{})
      {:error, %Jido.Action.Error.InvalidInputError{}}
  """
  def wrap_result(ash_result, jido_config \\ %{}) do
    case ash_result do
      # Already wrapped success results
      {:ok, data} ->
        converted_data = maybe_convert_to_maps(data, jido_config)
        {:ok, converted_data}

      # Already wrapped error results
      {:error, ash_error} when is_exception(ash_error) ->
        jido_error = AshJido.Error.from_ash(ash_error)
        {:error, jido_error}

      {:error, error} ->
        {:error, error}

      # Raw :ok atom from Ash.destroy!
      :ok ->
        {:ok, %{deleted: true}}

      # Handle direct data (for Ash.read! returning raw lists)
      data when not is_tuple(data) ->
        converted_data = maybe_convert_to_maps(data, jido_config)
        {:ok, converted_data}
    end
  end

  defp maybe_convert_to_maps(data, %{output_map?: false}), do: ensure_map_output(data)

  defp maybe_convert_to_maps(data, _config) do
    data
    |> convert_to_maps()
    |> ensure_map_output()
  end

  defp convert_to_maps(data) when is_list(data) do
    Enum.map(data, &convert_to_maps/1)
  end

  defp convert_to_maps(%Ash.Page.Offset{} = page) do
    %{
      results: convert_to_maps(page.results),
      limit: page.limit,
      offset: page.offset,
      count: page.count,
      more?: page.more?
    }
  end

  defp convert_to_maps(%Ash.Page.Keyset{} = page) do
    %{
      results: convert_to_maps(page.results),
      limit: page.limit,
      before: page.before,
      after: page.after,
      count: page.count,
      more?: page.more?
    }
  end

  defp convert_to_maps(%_{} = struct) do
    if is_ash_resource?(struct) do
      struct_to_map(struct)
    else
      struct
    end
  end

  # Pass through maps and primitives unchanged during recursive conversion
  defp convert_to_maps(data), do: data

  defp is_ash_resource?(struct) do
    function_exported?(struct.__struct__, :spark_dsl_config, 0)
  end

  defp struct_to_map(%_{} = struct) do
    public_fields = public_field_names(struct.__struct__)

    struct
    |> Map.from_struct()
    |> Map.drop(@ash_meta_keys)
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      if MapSet.member?(public_fields, key) and loaded?(value) do
        Map.put(acc, key, convert_to_maps(value))
      else
        acc
      end
    end)
  end

  defp public_field_names(resource) do
    attributes = resource |> Ash.Resource.Info.public_attributes() |> Enum.map(& &1.name)
    relationships = resource |> Ash.Resource.Info.public_relationships() |> Enum.map(& &1.name)
    calculations = resource |> Ash.Resource.Info.public_calculations() |> Enum.map(& &1.name)
    aggregates = resource |> Ash.Resource.Info.public_aggregates() |> Enum.map(& &1.name)

    MapSet.new(attributes ++ relationships ++ calculations ++ aggregates)
  end

  defp loaded?(%Ash.NotLoaded{}), do: false
  defp loaded?(_value), do: true

  # Ensures the final output is a map to satisfy Jido.Exec output validation.
  # Maps (including structs) pass through; all other values (lists, scalars,
  # nil) are wrapped in %{result: value}.
  defp ensure_map_output(data) when is_map(data), do: data
  defp ensure_map_output(data), do: %{result: data}
end
