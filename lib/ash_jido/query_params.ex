defmodule AshJido.QueryParams do
  @moduledoc false

  @query_param_keys [:filter, :sort, :limit, :offset, :load]
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

    [
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
      ],
      load: [
        type: :any,
        required: false,
        doc:
          "Relationships/calculations to load. " <>
            "Examples: :author, [:author, :comments], [author: [:profile]]. " <>
            "Merged with any static load configured on the action."
      ]
    ]
  end

  @doc false
  @spec normalize_keys(map()) :: map()
  def normalize_keys(params) do
    Enum.reduce(@query_param_keys, params, fn key, acc ->
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
    {query_opts_map, action_params} = Map.split(params, @query_param_keys)

    query_opts =
      query_opts_map
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
      |> enforce_max_page_size(jido_config)

    {query_opts, action_params}
  end

  def split(params, _jido_config), do: {%{}, params}

  @doc false
  @spec apply_to_query(Ash.Query.t(), map()) :: Ash.Query.t()
  def apply_to_query(query, query_opts) when map_size(query_opts) == 0, do: query

  def apply_to_query(query, query_opts) do
    Enum.reduce(query_opts, query, fn
      {:filter, filter_map}, query -> Ash.Query.filter_input(query, filter_map)
      {:sort, sort_value}, query -> Ash.Query.sort_input(query, normalize_sort_input(sort_value))
      {:limit, limit}, query -> Ash.Query.limit(query, limit)
      {:offset, offset}, query -> Ash.Query.offset(query, offset)
      {:load, load}, query -> Ash.Query.load(query, load)
      _, query -> query
    end)
  end

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
end
