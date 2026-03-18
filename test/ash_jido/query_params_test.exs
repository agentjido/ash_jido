defmodule AshJido.QueryParamsTest do
  @moduledoc """
  Tests for query parameter support on read actions.
  """
  use ExUnit.Case, async: false
  @moduletag :capture_log

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

      assert schema[:filter][:type] == :map
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
end