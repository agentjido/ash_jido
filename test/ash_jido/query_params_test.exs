defmodule AshJido.QueryParamsTest do
  use ExUnit.Case, async: true

  alias AshJido.QueryParams
  alias AshJido.Test.User

  @config %{
    filters: [:name, :active],
    sorts: [:name, :age],
    loads: [:posts, profile: [:avatar]],
    pagination: [type: :both, max_page_size: 25]
  }

  test "builds a schema for each enabled query control" do
    schema = QueryParams.schema(@config)

    assert Map.keys(schema) |> Enum.sort() ==
             [:after, :before, :count, :filter, :limit, :load, :offset, :sort]

    assert QueryParams.schema(%{}) == %{}

    assert Map.keys(QueryParams.schema(%{@config | pagination: [type: :keyset]})) |> Enum.sort() ==
             [:after, :before, :filter, :load, :limit, :sort, :count] |> Enum.sort()

    assert Map.keys(QueryParams.schema(%{pagination: [type: :offset]})) |> Enum.sort() ==
             [:count, :limit, :offset]

    assert QueryParams.schema(nil) == %{}
  end

  test "normalizes string query keys and keeps atom keys" do
    assert QueryParams.normalize_keys(%{"limit" => 2, "name" => "Ada"}) == %{
             "name" => "Ada",
             limit: 2
           }

    assert QueryParams.normalize_keys(%{"limit" => 2, limit: 3}) == %{limit: 3}
  end

  test "splits query controls, removes nils, and limits page size" do
    params = %{
      filter: %{"and" => [%{"active" => true}, %{name: "Ada"}]},
      sort: [%{"field" => "name", "direction" => "desc"}],
      limit: 200,
      offset: nil,
      action_argument: "value"
    }

    assert {query, %{action_argument: "value"}} = QueryParams.split(params, @config)
    assert query.limit == 25
    refute Map.has_key?(query, :offset)
  end

  test "rejects filter and sort fields outside their allowlists" do
    assert {%{filter: true}, %{}} = QueryParams.split(%{filter: true}, @config)

    assert_raise ArgumentError, ~r/filter field :secret is not allowed/, fn ->
      QueryParams.split(%{filter: %{or: [%{active: true}, %{secret: true}]}}, @config)
    end

    assert_raise ArgumentError, ~r/sort field/, fn ->
      QueryParams.split(%{sort: [%{field: :secret, direction: :asc}]}, @config)
    end
  end

  test "applies filters, string sort directions, and pagination" do
    query =
      User
      |> Ash.Query.new()
      |> QueryParams.apply_to_query(
        %{
          filter: %{active: true},
          sort: [%{field: "name", direction: "desc_nils_last"}],
          limit: 10,
          offset: 0,
          count: true
        },
        @config
      )

    assert query.filter
    assert query.sort != []
    assert Keyword.equal?(query.page, limit: 10, offset: 0, count: true)

    query =
      User
      |> Ash.Query.new()
      |> QueryParams.apply_to_query(%{sort: [%{field: :age}], ignored: true}, @config)

    assert query.sort != []
  end

  test "normalizes allowed flat and nested loads" do
    query =
      User
      |> Ash.Query.new()
      |> QueryParams.apply_to_query(%{load: :age}, %{@config | loads: [:age]})

    assert query.errors == []

    assert_raise ArgumentError, ~r/load profile.secret is not allowed/, fn ->
      User
      |> Ash.Query.new()
      |> QueryParams.apply_to_query(%{load: [profile: [:secret]]}, @config)
    end

    assert_raise ArgumentError, ~r/load posts is not allowed/, fn ->
      User
      |> Ash.Query.new()
      |> QueryParams.apply_to_query(%{load: [posts: [:child]]}, @config)
    end

    assert_raise ArgumentError, ~r/load unknown is not allowed/, fn ->
      User
      |> Ash.Query.new()
      |> QueryParams.apply_to_query(%{load: :unknown}, @config)
    end

    nested =
      User
      |> Ash.Query.new()
      |> QueryParams.apply_to_query(
        %{load: %{profile: [:avatar]}},
        %{@config | loads: [profile: [:avatar]]}
      )

    assert nested.errors != []

    assert_raise ArgumentError, ~r/load  is not allowed/, fn ->
      User
      |> Ash.Query.new()
      |> QueryParams.apply_to_query(%{load: 123}, %{@config | loads: [123]})
    end
  end
end
