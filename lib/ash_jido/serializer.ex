defmodule AshJido.Serializer do
  @moduledoc false

  @ash_meta_keys [
    :__meta__,
    :__metadata__,
    :aggregates,
    :calculations,
    :__order__,
    :__lateral_join_source__
  ]

  @doc false
  @spec envelope(term(), term()) :: map()
  def envelope(value, metadata \\ nil)

  def envelope(%Ash.Page.Offset{} = page, metadata) do
    %{
      result: serialize(page.results),
      page: %{
        type: :offset,
        limit: page.limit,
        offset: page.offset,
        count: page.count,
        more?: page.more?
      },
      metadata: serialize(metadata)
    }
  end

  def envelope(%Ash.Page.Keyset{} = page, metadata) do
    %{
      result: serialize(page.results),
      page: %{
        type: :keyset,
        limit: page.limit,
        before: page.before,
        after: page.after,
        count: page.count,
        more?: page.more?
      },
      metadata: serialize(metadata)
    }
  end

  def envelope(value, metadata) do
    %{result: serialize(value), page: nil, metadata: serialize(metadata)}
  end

  @doc false
  @spec serialize(term()) :: term()
  def serialize(nil), do: nil
  def serialize(%Ash.NotLoaded{}), do: nil
  def serialize(%Ash.ForbiddenField{}), do: nil
  def serialize(%Decimal{} = value), do: Decimal.to_string(value)
  def serialize(%Date{} = value), do: Date.to_iso8601(value)
  def serialize(%Time{} = value), do: Time.to_iso8601(value)
  def serialize(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def serialize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def serialize(%MapSet{} = value), do: value |> MapSet.to_list() |> serialize()
  def serialize(values) when is_list(values), do: Enum.map(values, &serialize/1)

  def serialize(%_{} = value) do
    if ash_resource?(value.__struct__) do
      serialize_resource(value)
    else
      value
      |> Map.from_struct()
      |> Map.drop(@ash_meta_keys)
      |> serialize()
    end
  end

  def serialize(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {key, serialize(nested)} end)
  end

  def serialize(value), do: value

  defp serialize_resource(record) do
    fields = serializable_fields(record.__struct__)

    record
    |> Map.from_struct()
    |> Map.drop(@ash_meta_keys)
    |> Enum.reduce(%{}, fn {key, value}, result ->
      if MapSet.member?(fields, key) and loaded?(value) do
        Map.put(result, key, serialize(value))
      else
        result
      end
    end)
  end

  defp serializable_fields(resource) do
    attributes =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.reject(& &1.sensitive?)
      |> Enum.map(& &1.name)

    relationships = resource |> Ash.Resource.Info.public_relationships() |> Enum.map(& &1.name)
    calculations = resource |> Ash.Resource.Info.public_calculations() |> Enum.map(& &1.name)
    aggregates = resource |> Ash.Resource.Info.public_aggregates() |> Enum.map(& &1.name)

    MapSet.new(attributes ++ relationships ++ calculations ++ aggregates)
  end

  defp ash_resource?(module) do
    function_exported?(module, :spark_dsl_config, 0)
  end

  defp loaded?(%Ash.NotLoaded{}), do: false
  defp loaded?(%Ash.ForbiddenField{}), do: false
  defp loaded?(_value), do: true
end
