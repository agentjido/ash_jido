defmodule AshJido.Mapper do
  @moduledoc """
  Handles conversion of Ash results to Jido-compatible formats.

  Converts Ash structs to maps (when configured) and wraps errors
  in Jido.Action.Error format via `AshJido.Error`.
  """

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

  ## Examples

      iex> AshJido.Mapper.wrap_result({:ok, %User{id: 1, name: "John"}}, %{output_map?: true})
      {:ok, %{id: 1, name: "John"}}

      iex> AshJido.Mapper.wrap_result({:error, %Ash.Error.Invalid{}}, %{})
      {:error, %Jido.Action.Error.InvalidInputError{}}
  """
  def wrap_result(ash_result, jido_config \\ %{}) do
    case ash_result do
      {:ok, data} ->
        converted_data = maybe_convert_to_maps(data, jido_config)
        {:ok, converted_data}

      {:error, ash_error} when is_exception(ash_error) ->
        jido_error = AshJido.Error.from_ash(ash_error)
        {:error, jido_error}

      {:error, error} ->
        {:error, error}

      # Handle direct data (for some Ash operations)
      data when not is_tuple(data) ->
        converted_data = maybe_convert_to_maps(data, jido_config)
        {:ok, converted_data}
    end
  end

  defp maybe_convert_to_maps(data, %{output_map?: false}), do: data
  defp maybe_convert_to_maps(data, _config), do: convert_to_maps(data)

  defp convert_to_maps(data) when is_list(data) do
    Enum.map(data, &convert_to_maps/1)
  end

  defp convert_to_maps(%_{} = struct) do
    if is_ash_resource?(struct) do
      struct_to_map(struct)
    else
      struct
    end
  end

  defp convert_to_maps(data), do: data

  defp is_ash_resource?(struct) do
    function_exported?(struct.__struct__, :spark_dsl_config, 0)
  end

  defp struct_to_map(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop(@ash_meta_keys)
    |> Enum.into(%{}, fn {k, v} -> {k, convert_to_maps(v)} end)
  end
end
