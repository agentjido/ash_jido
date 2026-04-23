defmodule AshJido.QueryParams do
  @moduledoc false

  @base_query_param_keys [:filter, :sort, :limit, :offset]
  @normalizable_query_param_keys @base_query_param_keys ++ [:load]
  @valid_sort_directions [
    :asc,
    :desc,
    :asc_nils_first,
    :asc_nils_last,
    :desc_nils_first,
    :desc_nils_last
  ]
  @sort_directions_by_name Map.new(@valid_sort_directions, &{Atom.to_string(&1), &1})

  @doc false
  @spec schema(AshJido.Resource.JidoAction.t()) :: keyword()
  def schema(jido_action) do
    max_page_doc =
      if jido_action.max_page_size do
        " Maximum: #{jido_action.max_page_size}."
      else
        ""
      end

    schema = [
      filter: [
        type: :any,
        required: false,
        doc:
          "Filter results using Ash's filter input syntax. " <>
            "Simple equality: %{\"name\" => \"fred\"}. " <>
            "Operators: %{\"age\" => %{\"greater_than\" => 25}}. " <>
            "In: %{\"status\" => %{\"in\" => [\"active\", \"pending\"]}}. " <>
            "Only public attributes are accessible."
      ],
      sort: [
        type: :any,
        required: false,
        doc:
          "Sort results. JSON list: [%{\"field\" => \"name\", \"direction\" => \"asc\"}]. " <>
            "Keyword list: [name: :asc, age: :desc]. " <>
            "String: \"name,-age\" (minus prefix = descending)."
      ],
      limit: [
        type: :pos_integer,
        required: false,
        doc: "Maximum number of results to return.#{max_page_doc}"
      ],
      offset: [
        type: :non_neg_integer,
        required: false,
        doc: "Number of results to skip."
      ]
    ]

    if dynamic_load_allowed?(jido_action) do
      schema ++
        [
          load: [
            type: :any,
            required: false,
            doc:
              "Relationships/calculations to load. " <>
                "Examples: :author, [:author, :comments], [author: [:profile]]. " <>
                "Merged with any static load configured on the action and constrained to configured `allowed_loads`."
          ]
        ]
    else
      schema
    end
  end

  @doc false
  @spec normalize_keys(map()) :: map()
  def normalize_keys(params) do
    Enum.reduce(@normalizable_query_param_keys, params, fn key, acc ->
      string_key = to_string(key)

      cond do
        Map.has_key?(acc, key) and Map.has_key?(acc, string_key) ->
          Map.delete(acc, string_key)

        Map.has_key?(acc, string_key) ->
          acc
          |> Map.put(key, Map.get(acc, string_key))
          |> Map.delete(string_key)

        true ->
          acc
      end
    end)
  end

  @doc false
  @spec split(map(), AshJido.Resource.JidoAction.t()) :: {map(), map()}
  def split(params, %{query_params?: true} = jido_config) do
    {query_opts_map, action_params} = Map.split(params, query_param_keys(jido_config))

    query_opts =
      query_opts_map
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
      |> enforce_max_page_size(jido_config)

    {query_opts, action_params}
  end

  def split(params, _jido_config), do: {%{}, params}

  @doc false
  @spec apply_to_query(Ash.Query.t(), map(), AshJido.Resource.JidoAction.t()) :: Ash.Query.t()
  def apply_to_query(query, query_opts, _jido_config) when map_size(query_opts) == 0,
    do: query

  def apply_to_query(query, query_opts, jido_config) do
    Enum.reduce(query_opts, query, fn
      {:filter, filter_map}, query -> Ash.Query.filter_input(query, filter_map)
      {:sort, sort_value}, query -> Ash.Query.sort_input(query, normalize_sort_input(sort_value))
      {:limit, limit}, query -> Ash.Query.limit(query, limit)
      {:offset, offset}, query -> Ash.Query.offset(query, offset)
      {:load, load}, query -> Ash.Query.load(query, normalize_dynamic_load!(load, jido_config))
      _, query -> query
    end)
  end

  defp query_param_keys(jido_config) do
    if dynamic_load_allowed?(jido_config) do
      @base_query_param_keys ++ [:load]
    else
      @base_query_param_keys
    end
  end

  defp dynamic_load_allowed?(%{allowed_loads: allowed_loads}) do
    not is_nil(allowed_loads) and allowed_loads != []
  end

  defp dynamic_load_allowed?(_), do: false

  defp enforce_max_page_size(query_opts, jido_config) do
    case jido_config.max_page_size do
      nil ->
        query_opts

      max when is_integer(max) ->
        case Map.get(query_opts, :limit) do
          limit when is_integer(limit) and limit > max ->
            Map.put(query_opts, :limit, max)

          _ ->
            query_opts
        end
    end
  end

  defp normalize_sort_input(sort) when is_list(sort) do
    cond do
      Keyword.keyword?(sort) ->
        sort

      true ->
        Enum.flat_map(sort, fn
          %{} = entry ->
            case Map.get(entry, :field) || Map.get(entry, "field") do
              nil ->
                []

              field ->
                direction =
                  entry
                  |> Map.get(:direction)
                  |> case do
                    nil -> Map.get(entry, "direction")
                    value -> value
                  end
                  |> normalize_sort_direction()

                [{field, direction}]
            end

          {field, direction} ->
            [{field, normalize_sort_direction(direction)}]

          entry when is_binary(entry) or is_atom(entry) ->
            [entry]

          _ ->
            []
        end)
    end
  end

  defp normalize_sort_input(sort), do: sort

  defp normalize_sort_direction(direction) when direction in @valid_sort_directions,
    do: direction

  defp normalize_sort_direction(direction) when is_binary(direction),
    do: Map.get(@sort_directions_by_name, direction, :asc)

  defp normalize_sort_direction(_), do: :asc

  defp normalize_dynamic_load!(load, %{allowed_loads: allowed_loads}) do
    allowed_tree = load_tree(allowed_loads)

    case normalize_load_statement(load, allowed_tree, []) do
      {:ok, normalized_load} ->
        normalized_load

      {:error, path} ->
        path = Enum.map_join(path, ".", &to_string/1)

        raise ArgumentError,
              "AshJido: dynamic load #{inspect(path)} is not allowed for this action"
    end
  end

  defp load_tree(loads) do
    loads
    |> List.wrap()
    |> Enum.reduce(%{}, &put_load_entry(&2, &1))
  end

  defp put_load_entry(tree, {field, nested}) do
    Map.put(tree, field, load_tree(nested))
  end

  defp put_load_entry(tree, field) when is_atom(field) or is_binary(field) do
    Map.put(tree, field, :leaf)
  end

  defp put_load_entry(tree, _unsupported), do: tree

  defp normalize_load_statement(load, allowed_tree, path)
       when is_atom(load) or is_binary(load) do
    with {:ok, field, _nested_tree} <- resolve_allowed_load(load, allowed_tree, path) do
      {:ok, field}
    end
  end

  defp normalize_load_statement(loads, allowed_tree, path) when is_list(loads) do
    loads
    |> Enum.reduce_while({:ok, []}, fn load, {:ok, acc} ->
      case normalize_load_entry(load, allowed_tree, path) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _path} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp normalize_load_statement(%{} = loads, allowed_tree, path) do
    loads
    |> Enum.to_list()
    |> normalize_load_statement(allowed_tree, path)
  end

  defp normalize_load_statement(_load, _allowed_tree, path), do: {:error, path}

  defp normalize_load_entry({field, nested}, allowed_tree, path) do
    with {:ok, resolved_field, nested_tree} <- resolve_allowed_load(field, allowed_tree, path),
         {:ok, normalized_nested} <-
           normalize_nested_load(nested, nested_tree, path ++ [resolved_field]) do
      {:ok, {resolved_field, normalized_nested}}
    end
  end

  defp normalize_load_entry(%{} = load, allowed_tree, path) do
    normalize_load_statement(load, allowed_tree, path)
  end

  defp normalize_load_entry(field, allowed_tree, path)
       when is_atom(field) or is_binary(field) do
    normalize_load_statement(field, allowed_tree, path)
  end

  defp normalize_load_entry(_unsupported, _allowed_tree, path), do: {:error, path}

  defp normalize_nested_load(nested, :leaf, _path) when nested in [[], %{}],
    do: {:ok, []}

  defp normalize_nested_load(_nested, :leaf, path), do: {:error, path}

  defp normalize_nested_load(nested, nested_tree, path) when is_map(nested_tree) do
    normalize_load_statement(nested, nested_tree, path)
  end

  defp resolve_allowed_load(field, allowed_tree, path) do
    case Enum.find(allowed_tree, fn {allowed_field, _nested} ->
           to_string(allowed_field) == to_string(field)
         end) do
      {allowed_field, nested_tree} -> {:ok, allowed_field, nested_tree}
      nil -> {:error, path ++ [field]}
    end
  end
end
