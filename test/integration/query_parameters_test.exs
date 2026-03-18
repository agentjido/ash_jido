defmodule AshJido.QueryParametersTest do
  use ExUnit.Case, async: false

  defmodule Item do
    use Ash.Resource,
      domain: nil,
      extensions: [AshJido],
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
      attribute(:price, :integer, allow_nil?: false, public?: true)
      attribute(:active, :boolean, default: true, public?: true)
    end

    actions do
      defaults([:read, :destroy])

      create :create do
        accept([:name, :price, :active])
      end

      read :by_name do
        argument(:name, :string, allow_nil?: false)

        filter(expr(name == ^arg(:name)))
      end
    end

    jido do
      all_actions()
    end
  end

  defmodule RestrictedItem do
    use Ash.Resource,
      domain: nil,
      extensions: [AshJido],
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
    end

    actions do
      defaults([:read])

      create :create do
        accept([:name])
      end
    end

    jido do
      action(:read, action_parameters: [:limit])
    end
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource(Item)
      resource(RestrictedItem)
    end
  end

  setup do
    # Seed test data
    items =
      for {name, price} <- [{"Apple", 5}, {"Banana", 3}, {"Cherry", 12}, {"Date", 8}] do
        Item
        |> Ash.Changeset.for_create(:create, %{name: name, price: price}, domain: Domain)
        |> Ash.create!(domain: Domain)
      end

    %{items: items}
  end

  describe "schema generation" do
    test "read actions include filter/sort/limit/offset in schema" do
      schema = Item.Jido.Read.schema()

      assert Keyword.has_key?(schema, :filter)
      assert Keyword.has_key?(schema, :sort)
      assert Keyword.has_key?(schema, :limit)
      assert Keyword.has_key?(schema, :offset)

      assert schema[:filter][:type] == :map
      assert schema[:limit][:type] == :non_neg_integer
      assert schema[:offset][:type] == :non_neg_integer
    end

    test "action_parameters: [:limit] only includes limit in schema" do
      schema = RestrictedItem.Jido.Read.schema()

      assert Keyword.has_key?(schema, :limit)
      refute Keyword.has_key?(schema, :filter)
      refute Keyword.has_key?(schema, :sort)
      refute Keyword.has_key?(schema, :offset)
    end

    test "create actions do not include query parameters" do
      schema = Item.Jido.Create.schema()

      refute Keyword.has_key?(schema, :filter)
      refute Keyword.has_key?(schema, :sort)
      refute Keyword.has_key?(schema, :limit)
      refute Keyword.has_key?(schema, :offset)
    end

    test "schema docs list public filterable attribute names" do
      schema = Item.Jido.Read.schema()
      filter_doc = schema[:filter][:doc]

      assert filter_doc =~ "name"
      assert filter_doc =~ "price"
      assert filter_doc =~ "active"
    end
  end

  describe "filter" do
    test "filter by equality", %{items: _items} do
      {:ok, results} =
        Item.Jido.Read.run(
          %{filter: %{name: %{eq: "Apple"}}},
          %{domain: Domain}
        )

      assert length(results) == 1
      assert hd(results)[:name] == "Apple"
    end

    test "filter by comparison", %{items: _items} do
      {:ok, results} =
        Item.Jido.Read.run(
          %{filter: %{price: %{gt: 10}}},
          %{domain: Domain}
        )

      assert length(results) == 1
      assert hd(results)[:name] == "Cherry"
    end
  end

  describe "sort" do
    test "sort ascending by name", %{items: _items} do
      {:ok, results} =
        Item.Jido.Read.run(
          %{sort: [%{field: :name, direction: :asc}]},
          %{domain: Domain}
        )

      names = Enum.map(results, & &1[:name])
      assert names == ["Apple", "Banana", "Cherry", "Date"]
    end

    test "sort descending by price", %{items: _items} do
      {:ok, results} =
        Item.Jido.Read.run(
          %{sort: [%{field: :price, direction: :desc}]},
          %{domain: Domain}
        )

      names = Enum.map(results, & &1[:name])
      assert names == ["Cherry", "Date", "Apple", "Banana"]
    end
  end

  describe "limit and offset" do
    test "limit returns correct count", %{items: _items} do
      {:ok, results} =
        Item.Jido.Read.run(
          %{limit: 2},
          %{domain: Domain}
        )

      assert length(results) == 2
    end

    test "offset skips correct count", %{items: _items} do
      {:ok, all} = Item.Jido.Read.run(%{}, %{domain: Domain})

      {:ok, results} =
        Item.Jido.Read.run(
          %{offset: 2},
          %{domain: Domain}
        )

      assert length(results) == length(all) - 2
    end
  end

  describe "combined parameters" do
    test "filter + sort + limit", %{items: _items} do
      {:ok, results} =
        Item.Jido.Read.run(
          %{
            filter: %{price: %{gte: 3}},
            sort: [%{field: :price, direction: :asc}],
            limit: 2
          },
          %{domain: Domain}
        )

      assert length(results) == 2
      names = Enum.map(results, & &1[:name])
      assert names == ["Banana", "Apple"]
    end
  end

  describe "action args coexist with query params" do
    test "by_name action argument works with limit", %{items: _items} do
      # Create a second Apple so limit has something to limit
      Item
      |> Ash.Changeset.for_create(:create, %{name: "Apple", price: 99}, domain: Domain)
      |> Ash.create!(domain: Domain)

      {:ok, results} =
        Item.Jido.ByName.run(
          %{name: "Apple", limit: 1},
          %{domain: Domain}
        )

      assert length(results) == 1
      assert hd(results)[:name] == "Apple"
    end
  end

  describe "empty/nil query params" do
    test "empty params are no-ops", %{items: _items} do
      {:ok, all} = Item.Jido.Read.run(%{}, %{domain: Domain})
      {:ok, with_empty} = Item.Jido.Read.run(%{filter: %{}}, %{domain: Domain})

      assert length(all) == length(with_empty)
    end
  end

  describe "string keys" do
    test "string keys work for query params", %{items: _items} do
      {:ok, results} =
        Item.Jido.Read.run(
          %{"filter" => %{"name" => %{"eq" => "Apple"}}, "limit" => 1},
          %{domain: Domain}
        )

      assert length(results) == 1
      assert hd(results)[:name] == "Apple"
    end
  end
end
