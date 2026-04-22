defmodule AshJido.ExecIntegrationTest do
  @moduledoc """
  Integration tests exercising generated AshJido actions through Jido.Exec.run/3.

  These tests verify that AshJido-generated actions produce outputs compatible
  with Jido.Exec's validation pipeline, which calls Map.split/2 on results
  and therefore requires map outputs.
  """

  use ExUnit.Case, async: false

  @moduletag :capture_log

  # ── Test resources ──────────────────────────────────────────────────

  defmodule ScalarResource do
    use Ash.Resource,
      domain: nil,
      extensions: [AshJido],
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false)
    end

    actions do
      defaults([:read])

      action :greet do
        description("Returns a greeting string")
        returns(:string)
        argument(:name, :string, allow_nil?: false)

        run(fn input, _context ->
          {:ok, "Hello, #{input.arguments.name}!"}
        end)
      end

      action :count do
        description("Returns an integer count")
        returns(:integer)

        run(fn _input, _context ->
          {:ok, 42}
        end)
      end

      action :check do
        description("Returns a boolean")
        returns(:boolean)

        run(fn _input, _context ->
          {:ok, true}
        end)
      end

      action :status do
        description("Returns an atom")
        returns(:atom)

        run(fn _input, _context ->
          {:ok, :active}
        end)
      end

      action :nothing do
        description("A void action that returns nothing")

        run(fn _input, _context ->
          :ok
        end)
      end

      action :get_tags do
        description("Returns a list of strings")
        returns({:array, :string})

        run(fn _input, _context ->
          {:ok, ["alpha", "beta", "gamma"]}
        end)
      end

      action :get_map do
        description("Returns a plain map")
        returns(:map)

        run(fn _input, _context ->
          {:ok, %{key: "value", count: 1}}
        end)
      end
    end

    jido do
      action(:greet, name: "greet_user")
      action(:count, name: "count_items")
      action(:check, name: "check_status")
      action(:status, name: "get_status")
      action(:nothing, name: "get_nothing")
      action(:get_tags, name: "list_tags")
      action(:get_map, name: "get_map_data")
    end
  end

  defmodule ScalarRawResource do
    @moduledoc "Same actions but with output_map?: false"
    use Ash.Resource,
      domain: nil,
      extensions: [AshJido],
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false)
    end

    actions do
      defaults([:read])

      action :greet do
        description("Returns a greeting string")
        returns(:string)
        argument(:name, :string, allow_nil?: false)

        run(fn input, _context ->
          {:ok, "Hello, #{input.arguments.name}!"}
        end)
      end

      action :get_tags do
        description("Returns a list of strings")
        returns({:array, :string})

        run(fn _input, _context ->
          {:ok, ["alpha", "beta", "gamma"]}
        end)
      end
    end

    jido do
      action(:greet, name: "greet_user_raw", output_map?: false)
      action(:get_tags, name: "list_tags_raw", output_map?: false)
    end
  end

  defmodule ExecTestDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource(ScalarResource)
      resource(ScalarRawResource)
    end
  end

  # ── Tests: output_map?: true (default) ─────────────────────────────

  describe "Jido.Exec.run/3 with output_map?: true (default)" do
    test "scalar string result passes through Jido.Exec validation" do
      action_module = ScalarResource.Jido.Greet

      result =
        Jido.Exec.run(action_module, %{name: "World"}, %{domain: ExecTestDomain})

      assert {:ok, %{result: "Hello, World!"}} = result
    end

    test "scalar integer result passes through Jido.Exec validation" do
      action_module = ScalarResource.Jido.Count

      result = Jido.Exec.run(action_module, %{}, %{domain: ExecTestDomain})

      assert {:ok, %{result: 42}} = result
    end

    test "scalar boolean result passes through Jido.Exec validation" do
      action_module = ScalarResource.Jido.Check

      result = Jido.Exec.run(action_module, %{}, %{domain: ExecTestDomain})

      assert {:ok, %{result: true}} = result
    end

    test "scalar atom result passes through Jido.Exec validation" do
      action_module = ScalarResource.Jido.Status

      result = Jido.Exec.run(action_module, %{}, %{domain: ExecTestDomain})

      assert {:ok, %{result: :active}} = result
    end

    test "void action result passes through Jido.Exec validation" do
      action_module = ScalarResource.Jido.Nothing

      result = Jido.Exec.run(action_module, %{}, %{domain: ExecTestDomain})

      # Ash.run_action! returns :ok for void actions,
      # generator wraps as {:ok, :ok}, mapper wraps atom as %{result: :ok}
      assert {:ok, %{result: :ok}} = result
    end

    test "list result passes through Jido.Exec validation" do
      action_module = ScalarResource.Jido.GetTags

      result = Jido.Exec.run(action_module, %{}, %{domain: ExecTestDomain})

      assert {:ok, %{result: ["alpha", "beta", "gamma"]}} = result
    end

    test "map result passes through Jido.Exec validation" do
      action_module = ScalarResource.Jido.GetMap

      result = Jido.Exec.run(action_module, %{}, %{domain: ExecTestDomain})

      assert {:ok, %{key: "value", count: 1}} = result
    end
  end

  # ── Tests: output_map?: false ──────────────────────────────────────

  describe "Jido.Exec.run/3 with output_map?: false" do
    test "scalar string result passes through Jido.Exec validation" do
      action_module = ScalarRawResource.Jido.Greet

      result =
        Jido.Exec.run(action_module, %{name: "World"}, %{domain: ExecTestDomain})

      assert {:ok, %{result: "Hello, World!"}} = result
    end

    test "list result passes through Jido.Exec validation" do
      action_module = ScalarRawResource.Jido.GetTags

      result = Jido.Exec.run(action_module, %{}, %{domain: ExecTestDomain})

      assert {:ok, %{result: ["alpha", "beta", "gamma"]}} = result
    end
  end
end
