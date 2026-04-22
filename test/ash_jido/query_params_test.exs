defmodule AshJido.QueryParamsTest do
  @moduledoc """
  Tests for query parameter support on read actions.
  """
  use ExUnit.Case, async: false
  @moduletag :capture_log

  describe "query parameter helpers" do
    test "normalizes string query parameter keys" do
      assert AshJido.QueryParams.normalize_keys(%{
               "filter" => %{"name" => "Alice"},
               "limit" => 1,
               name: "kept"
             }) == %{
               filter: %{"name" => "Alice"},
               limit: 1,
               name: "kept"
             }
    end

    test "keeps atom query parameter values when atom and string keys both exist" do
      assert AshJido.QueryParams.normalize_keys(%{
               "filter" => %{name: "Bob"},
               filter: %{name: "Alice"}
             }) == %{filter: %{name: "Alice"}}
    end

    test "splits query params from action params and enforces max page size" do
      config = %AshJido.Resource.JidoAction{query_params?: true, max_page_size: 2}

      assert {%{filter: %{name: "Alice"}, limit: 2}, %{name: "Action Arg"}} =
               AshJido.QueryParams.split(
                 %{filter: %{name: "Alice"}, limit: 10, sort: nil, name: "Action Arg"},
                 config
               )
    end

    test "leaves params untouched when query params are disabled" do
      config = %AshJido.Resource.JidoAction{query_params?: false}
      params = %{filter: %{name: "Alice"}, name: "Action Arg"}

      assert {%{}, ^params} = AshJido.QueryParams.split(params, config)
    end
  end

  describe "schema generation" do
    test "read actions include query params in schema by default" do
      # AshJido.Test.User has `action(:read)` in its jido section
      # The generated module is AshJido.Test.User.Jido.Read
      module = AshJido.Test.User.Jido.Read
      schema = module.schema()

      assert Keyword.has_key?(schema, :filter)
      assert Keyword.has_key?(schema, :sort)
      assert Keyword.has_key?(schema, :limit)
      assert Keyword.has_key?(schema, :offset)
      assert Keyword.has_key?(schema, :load)
    end

    test "query param schema entries have correct types" do
      schema = AshJido.Test.User.Jido.Read.schema()

      assert schema[:filter][:type] == :any
      assert schema[:limit][:type] == :pos_integer
      assert schema[:offset][:type] == :non_neg_integer
    end

    test "query params are not required" do
      schema = AshJido.Test.User.Jido.Read.schema()

      refute schema[:filter][:required]
      refute schema[:sort][:required]
      refute schema[:limit][:required]
      refute schema[:offset][:required]
      refute schema[:load][:required]
    end

    test "query param docs are present" do
      schema = AshJido.Test.User.Jido.Read.schema()

      assert is_binary(schema[:filter][:doc])
      assert is_binary(schema[:sort][:doc])
      assert is_binary(schema[:limit][:doc])
      assert is_binary(schema[:offset][:doc])
      assert is_binary(schema[:load][:doc])
    end

    test "non-read actions do NOT include query params" do
      # AshJido.Test.User.Jido.Register is a create action
      schema = AshJido.Test.User.Jido.Register.schema()

      refute Keyword.has_key?(schema, :filter)
      refute Keyword.has_key?(schema, :sort)
      refute Keyword.has_key?(schema, :limit)
      refute Keyword.has_key?(schema, :offset)
      refute Keyword.has_key?(schema, :load)
    end

    test "read actions with arguments include both args and query params" do
      # AshJido.Test.User.Jido.ByEmail has an :email argument
      schema = AshJido.Test.User.Jido.ByEmail.schema()

      # Action argument
      assert Keyword.has_key?(schema, :email)
      # Query params
      assert Keyword.has_key?(schema, :filter)
      assert Keyword.has_key?(schema, :sort)
    end
  end

  describe "query_params? opt-out" do
    test "read action with query_params?: false excludes query params from schema" do
      dsl_state = AshJido.Test.User.spark_dsl_config()

      jido_action = %AshJido.Resource.JidoAction{
        action: :read,
        name: "list_no_query_params",
        module_name: TestNoQueryParamsReadAction,
        description: "List without query params",
        output_map?: true,
        query_params?: false
      }

      module_name =
        AshJido.Generator.generate_jido_action_module(
          AshJido.Test.User,
          jido_action,
          dsl_state
        )

      schema = module_name.schema()
      refute Keyword.has_key?(schema, :filter)
      refute Keyword.has_key?(schema, :sort)
      refute Keyword.has_key?(schema, :limit)
      refute Keyword.has_key?(schema, :offset)
      refute Keyword.has_key?(schema, :load)
    end
  end

  describe "validation: string keys" do
    test "query param keys are normalized before validation" do
      assert {:ok, validated} =
               AshJido.Test.User.Jido.Read.validate_params(%{
                 "filter" => %{"name" => "Alice"},
                 "limit" => 1,
                 "offset" => 0
               })

      assert validated == %{
               filter: %{"name" => "Alice"},
               limit: 1,
               offset: 0
             }
    end
  end

  describe "runtime: filter" do
    setup :create_test_users

    test "filters by exact equality", %{users: _users} do
      {:ok, %{result: result}} =
        AshJido.Test.User.Jido.Read.run(
          %{filter: %{name: "Alice"}},
          %{domain: AshJido.Test.Domain}
        )

      assert length(result) == 1
      assert hd(result)[:name] == "Alice"
    end

    test "filters with greater_than operator", %{users: _users} do
      {:ok, %{result: result}} =
        AshJido.Test.User.Jido.Read.run(
          %{filter: %{age: %{greater_than: 28}}},
          %{domain: AshJido.Test.Domain}
        )

      # Alice (30) and Charlie (35)
      assert length(result) == 2
      names = Enum.map(result, & &1[:name]) |> Enum.sort()
      assert names == ["Alice", "Charlie"]
    end

    test "filters with in operator", %{users: _users} do
      {:ok, %{result: result}} =
        AshJido.Test.User.Jido.Read.run(
          %{filter: %{name: %{in: ["Alice", "Bob"]}}},
          %{domain: AshJido.Test.Domain}
        )

      assert length(result) == 2
    end

    test "filters with multiple conditions (AND)", %{users: _users} do
      {:ok, %{result: result}} =
        AshJido.Test.User.Jido.Read.run(
          %{filter: %{active: true, age: %{greater_than: 28}}},
          %{domain: AshJido.Test.Domain}
        )

      # Alice is 30 and active, Charlie is 35 and active
      assert length(result) == 2
    end
  end

  describe "runtime: sort" do
    setup :create_test_users

    test "sorts ascending", %{users: _users} do
      {:ok, %{result: result}} =
        AshJido.Test.User.Jido.Read.run(
          %{sort: [age: :asc]},
          %{domain: AshJido.Test.Domain}
        )

      ages = Enum.map(result, & &1[:age])
      assert ages == [25, 30, 35]
    end

    test "sorts descending", %{users: _users} do
      {:ok, %{result: result}} =
        AshJido.Test.User.Jido.Read.run(
          %{sort: [age: :desc]},
          %{domain: AshJido.Test.Domain}
        )

      ages = Enum.map(result, & &1[:age])
      assert ages == [35, 30, 25]
    end

    test "sorts using JSON-style sort entries", %{users: _users} do
      {:ok, %{result: result}} =
        AshJido.Test.User.Jido.Read.run(
          %{sort: [%{"field" => "age", "direction" => "desc"}]},
          %{domain: AshJido.Test.Domain}
        )

      ages = Enum.map(result, & &1[:age])
      assert ages == [35, 30, 25]
    end
  end

  describe "runtime: limit and offset" do
    setup :create_test_users

    test "limits results", %{users: _users} do
      {:ok, %{result: result}} =
        AshJido.Test.User.Jido.Read.run(
          %{sort: [age: :asc], limit: 2},
          %{domain: AshJido.Test.Domain}
        )

      assert length(result) == 2
    end

    test "offsets results", %{users: _users} do
      {:ok, %{result: result}} =
        AshJido.Test.User.Jido.Read.run(
          %{sort: [age: :asc], offset: 1},
          %{domain: AshJido.Test.Domain}
        )

      assert length(result) == 2
      assert hd(result)[:age] == 30
    end

    test "combines limit and offset", %{users: _users} do
      {:ok, %{result: result}} =
        AshJido.Test.User.Jido.Read.run(
          %{sort: [age: :asc], limit: 1, offset: 1},
          %{domain: AshJido.Test.Domain}
        )

      assert length(result) == 1
      assert hd(result)[:name] == "Alice"
    end
  end

  describe "runtime: combined params" do
    setup :create_test_users

    test "filter + sort + limit", %{users: _users} do
      {:ok, %{result: result}} =
        AshJido.Test.User.Jido.Read.run(
          %{filter: %{active: true}, sort: [age: :desc], limit: 2},
          %{domain: AshJido.Test.Domain}
        )

      assert length(result) == 2
      ages = Enum.map(result, & &1[:age])
      assert ages == [35, 30]
    end
  end

  describe "runtime: no query params" do
    setup :create_test_users

    test "works normally without query params", %{users: _users} do
      {:ok, %{result: result}} =
        AshJido.Test.User.Jido.Read.run(
          %{},
          %{domain: AshJido.Test.Domain}
        )

      # Should return all 3 users
      assert length(result) == 3
    end
  end

  describe "runtime: string keys" do
    setup :create_test_users

    test "extracts string-keyed filter and limit params", %{users: _users} do
      {:ok, %{result: result}} =
        AshJido.Test.User.Jido.Read.run(
          %{"filter" => %{"name" => "Alice"}, "limit" => 1},
          %{domain: AshJido.Test.Domain}
        )

      assert length(result) == 1
      assert hd(result)[:name] == "Alice"
    end

    test "extracts string-keyed sort params", %{users: _users} do
      {:ok, %{result: result}} =
        AshJido.Test.User.Jido.Read.run(
          %{"sort" => [%{"field" => "age", "direction" => "desc"}]},
          %{domain: AshJido.Test.Domain}
        )

      ages = Enum.map(result, & &1[:age])
      assert ages == [35, 30, 25]
    end
  end

  describe "runtime: max_page_size enforcement" do
    setup :create_test_users

    test "clamps limit to max_page_size", %{users: _users} do
      dsl_state = AshJido.Test.User.spark_dsl_config()

      jido_action = %AshJido.Resource.JidoAction{
        action: :read,
        name: "list_with_max_page",
        module_name: TestMaxPageSizeReadAction,
        description: "List with max page size",
        output_map?: true,
        query_params?: true,
        max_page_size: 2
      }

      module_name =
        AshJido.Generator.generate_jido_action_module(
          AshJido.Test.User,
          jido_action,
          dsl_state
        )

      # Request limit: 100, but max_page_size is 2
      {:ok, %{result: result}} =
        module_name.run(
          %{sort: [age: :asc], limit: 100},
          %{domain: AshJido.Test.Domain}
        )

      assert length(result) == 2
    end

    test "does not clamp when limit is within max_page_size", %{users: _users} do
      dsl_state = AshJido.Test.User.spark_dsl_config()

      jido_action = %AshJido.Resource.JidoAction{
        action: :read,
        name: "list_with_max_page2",
        module_name: TestMaxPageSize2ReadAction,
        description: "List with max page size",
        output_map?: true,
        query_params?: true,
        max_page_size: 10
      }

      module_name =
        AshJido.Generator.generate_jido_action_module(
          AshJido.Test.User,
          jido_action,
          dsl_state
        )

      # Request limit: 2, which is within max_page_size 10
      {:ok, %{result: result}} =
        module_name.run(
          %{sort: [age: :asc], limit: 2},
          %{domain: AshJido.Test.Domain}
        )

      assert length(result) == 2
    end
  end

  defp create_test_users(_context) do
    opts = [domain: AshJido.Test.Domain]

    user1 =
      AshJido.Test.User
      |> Ash.Changeset.for_create(
        :register,
        %{name: "Alice", email: "alice@example.com", age: 30},
        opts
      )
      |> Ash.create!(opts)

    user2 =
      AshJido.Test.User
      |> Ash.Changeset.for_create(
        :register,
        %{name: "Bob", email: "bob@example.com", age: 25},
        opts
      )
      |> Ash.create!(opts)

    user3 =
      AshJido.Test.User
      |> Ash.Changeset.for_create(
        :register,
        %{
          name: "Charlie",
          email: "charlie@example.com",
          age: 35
        },
        opts
      )
      |> Ash.create!(opts)

    %{users: [user1, user2, user3]}
  end
end
