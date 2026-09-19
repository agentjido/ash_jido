defmodule AshJido.QueryParams do
  @moduledoc false

  @valid_sort_directions [
    :asc,
    :desc,
    :asc_nils_first,
    :asc_nils_last,
    :desc_nils_first,
    :desc_nils_last
  ]
  @sort_directions_by_name Map.new(@valid_sort_directions, &{Atom.to_string(&1), &1})
  @logical_filter_keys ["and", "or", "not"]

  @doc false
  @spec schema(struct() | map()) :: %{atom() => Zoi.schema()}
  def schema(config) do
    %{}
    |> maybe_put_filter(config)
    |> maybe_put_sort(config)
    |> maybe_put_load(config)
    |> put_pagination(config)
  end

  @doc false
  @spec normalize_keys(map()) :: map()
  def normalize_keys(params) do
    schema_keys = [:filter, :sort, :load, :limit, :offset, :before, :after, :count]

    Enum.reduce(schema_keys, params, fn key, result ->
      string_key = to_string(key)

      cond do
        Map.has_key?(result, key) ->
          Map.delete(result, string_key)

        Map.has_key?(result, string_key) ->
          result |> Map.put(key, Map.get(result, string_key)) |> Map.delete(string_key)

        true ->
          result
      end
    end)
  end

  @doc false
  @spec split(map(), struct() | map()) :: {map(), map()}
  def split(params, config) do
    keys = Map.keys(schema(config))
    {query_params, action_params} = Map.split(params, keys)

    query_params =
      query_params
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
      |> validate_filter!(config)
      |> validate_sort!(config)
      |> enforce_max_page_size(config)

    {query_params, action_params}
  end

  @doc false
  @spec apply_to_query(Ash.Query.t(), map(), struct() | map()) :: Ash.Query.t()
  def apply_to_query(query, query_params, config) do
    {page_params, query_params} = Map.split(query_params, [:limit, :offset, :before, :after, :count])

    query =
      Enum.reduce(query_params, query, fn
        {:filter, filter}, query -> Ash.Query.filter_input(query, filter)
        {:sort, sort}, query -> Ash.Query.sort_input(query, normalize_sort_input(sort, config))
        {:load, load}, query -> Ash.Query.load(query, normalize_dynamic_load!(load, config))
        _entry, query -> query
      end)

    if map_size(page_params) == 0 do
      query
    else
      Ash.Query.page(query, Map.to_list(page_params))
    end
  end

  defp maybe_put_filter(schema, config) do
    if allowed(config, :filters) == [] do
      schema
    else
      Map.put(schema, :filter, Zoi.map() |> Zoi.optional())
    end
  end

  defp maybe_put_sort(schema, config) do
    if allowed(config, :sorts) == [] do
      schema
    else
      sort_entry =
        Zoi.object(%{
          field: Zoi.union([Zoi.atom(), Zoi.string()]),
          direction: Zoi.enum(@valid_sort_directions ++ Enum.map(@valid_sort_directions, &to_string/1))
        })

      Map.put(schema, :sort, Zoi.array(sort_entry) |> Zoi.optional())
    end
  end

  defp maybe_put_load(schema, config) do
    if allowed(config, :loads) in [nil, []] do
      schema
    else
      Map.put(schema, :load, Zoi.any() |> Zoi.optional())
    end
  end

  defp put_pagination(schema, config) do
    case config_value(config, :pagination) do
      nil ->
        schema

      pagination ->
        schema
        |> Map.put(:limit, Zoi.integer() |> Zoi.min(1) |> Zoi.optional())
        |> maybe_put_offset(pagination)
        |> maybe_put_keyset(pagination)
        |> Map.put(:count, Zoi.boolean() |> Zoi.optional())
    end
  end

  defp maybe_put_offset(schema, pagination) do
    if Keyword.get(pagination, :type, :offset) in [:offset, :both] do
      Map.put(schema, :offset, Zoi.integer() |> Zoi.min(0) |> Zoi.optional())
    else
      schema
    end
  end

  defp maybe_put_keyset(schema, pagination) do
    if Keyword.get(pagination, :type, :offset) in [:keyset, :both] do
      schema
      |> Map.put(:before, Zoi.string() |> Zoi.optional())
      |> Map.put(:after, Zoi.string() |> Zoi.optional())
    else
      schema
    end
  end

  defp validate_filter!(query_params, config) do
    case Map.fetch(query_params, :filter) do
      :error ->
        query_params

      {:ok, filter} ->
        allowed_names = MapSet.new(allowed(config, :filters), &to_string/1)

        case invalid_filter_field(filter, allowed_names) do
          nil -> query_params
          field -> raise ArgumentError, "AshJido: filter field #{inspect(field)} is not allowed"
        end
    end
  end

  defp invalid_filter_field(filters, allowed_names) when is_list(filters) do
    Enum.find_value(filters, &invalid_filter_field(&1, allowed_names))
  end

  defp invalid_filter_field(filters, allowed_names) when is_map(filters) do
    Enum.find_value(filters, fn {field, value} ->
      field_name = to_string(field)

      cond do
        field_name in @logical_filter_keys -> invalid_filter_field(value, allowed_names)
        MapSet.member?(allowed_names, field_name) -> nil
        true -> field
      end
    end)
  end

  defp invalid_filter_field(_value, _allowed_names), do: nil

  defp validate_sort!(query_params, config) do
    case Map.fetch(query_params, :sort) do
      :error ->
        query_params

      {:ok, sort} ->
        allowed_names = MapSet.new(allowed(config, :sorts), &to_string/1)

        case Enum.find(sort, fn entry ->
               field = Map.get(entry, :field) || Map.get(entry, "field")
               not MapSet.member?(allowed_names, to_string(field))
             end) do
          nil -> query_params
          entry -> raise ArgumentError, "AshJido: sort field #{inspect(entry)} is not allowed"
        end
    end
  end

  defp normalize_sort_input(sort, config) do
    Enum.map(sort, fn entry ->
      field = Map.get(entry, :field) || Map.get(entry, "field")
      direction = Map.get(entry, :direction) || Map.get(entry, "direction") || :asc
      {resolve_allowed_name!(field, config), normalize_sort_direction(direction)}
    end)
  end

  defp resolve_allowed_name!(field, config) do
    Enum.find(allowed(config, :sorts), fn allowed_field ->
      to_string(allowed_field) == to_string(field)
    end) || raise ArgumentError, "AshJido: sort field #{inspect(field)} is not allowed"
  end

  defp normalize_sort_direction(direction) when direction in @valid_sort_directions, do: direction

  defp normalize_sort_direction(direction) when is_binary(direction),
    do: Map.fetch!(@sort_directions_by_name, direction)

  defp enforce_max_page_size(query_params, config) do
    max_page_size =
      config
      |> config_value(:pagination)
      |> case do
        pagination when is_list(pagination) -> Keyword.get(pagination, :max_page_size)
        _other -> nil
      end

    case {Map.get(query_params, :limit), max_page_size} do
      {limit, max} when is_integer(limit) and is_integer(max) and limit > max -> Map.put(query_params, :limit, max)
      _other -> query_params
    end
  end

  defp normalize_dynamic_load!(load, config) do
    allowed_tree = load_tree(allowed(config, :loads))

    case normalize_load_statement(load, allowed_tree, []) do
      {:ok, normalized} -> normalized
      {:error, path} -> raise ArgumentError, "AshJido: load #{Enum.join(path, ".")} is not allowed"
    end
  end

  defp load_tree(loads) do
    loads |> List.wrap() |> Enum.reduce(%{}, &put_load_entry(&2, &1))
  end

  defp put_load_entry(tree, {field, nested}), do: Map.put(tree, field, load_tree(nested))
  defp put_load_entry(tree, field) when is_atom(field) or is_binary(field), do: Map.put(tree, field, :leaf)
  defp put_load_entry(tree, _unsupported), do: tree

  defp normalize_load_statement(load, allowed_tree, path) when is_atom(load) or is_binary(load) do
    case resolve_allowed(load, allowed_tree, path) do
      {:ok, field, _nested} -> {:ok, field}
      {:error, _path} = error -> error
    end
  end

  defp normalize_load_statement(loads, allowed_tree, path) when is_list(loads) do
    Enum.reduce_while(loads, {:ok, []}, fn load, {:ok, result} ->
      case normalize_load_entry(load, allowed_tree, path) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | result]}}
        {:error, _path} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, result} -> {:ok, Enum.reverse(result)}
      error -> error
    end
  end

  defp normalize_load_statement(loads, allowed_tree, path) when is_map(loads) do
    normalize_load_statement(Map.to_list(loads), allowed_tree, path)
  end

  defp normalize_load_statement(_load, _allowed_tree, path), do: {:error, path}

  defp normalize_load_entry({field, nested}, allowed_tree, path) do
    with {:ok, resolved, nested_tree} <- resolve_allowed(field, allowed_tree, path),
         {:ok, normalized} <- normalize_nested_load(nested, nested_tree, path ++ [resolved]) do
      {:ok, {resolved, normalized}}
    end
  end

  defp normalize_load_entry(field, allowed_tree, path),
    do: normalize_load_statement(field, allowed_tree, path)

  defp normalize_nested_load(nested, :leaf, _path) when nested in [[], %{}], do: {:ok, []}
  defp normalize_nested_load(_nested, :leaf, path), do: {:error, path}
  defp normalize_nested_load(nested, tree, path), do: normalize_load_statement(nested, tree, path)

  defp resolve_allowed(field, allowed_tree, path) do
    case Enum.find(allowed_tree, fn {allowed_field, _nested} -> to_string(allowed_field) == to_string(field) end) do
      {allowed_field, nested} -> {:ok, allowed_field, nested}
      nil -> {:error, path ++ [field]}
    end
  end

  defp allowed(config, key), do: config_value(config, key, []) || []
  defp config_value(config, key, default \\ nil)
  defp config_value(nil, _key, default), do: default
  defp config_value(config, key, default), do: Map.get(config, key, default)
end
