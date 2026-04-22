defmodule AshJido.MultipleJidoEntriesTest do
  @moduledoc """
  Regression tests for agentjido/ash_jido#19.

  A resource may declare more than one `jido` action entry that targets
  the same underlying Ash action, distinguishing the entries by their
  `name:` and explicit `module_name:`. The generator must produce one
  distinct module per entry while preserving legacy default module names,
  and refuse to compile a resource whose entries resolve to the same
  module.
  """

  # Code generation and DSL compilation touch global state.
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias AshJido.Test.MultiJidoItem

  describe "multiple jido entries targeting the same Ash action" do
    test "produce one distinct generated module per entry" do
      generated_modules =
        MultiJidoItem.spark_dsl_config()
        |> Spark.Dsl.Extension.get_persisted(:generated_jido_modules)
        |> List.wrap()
        |> Enum.uniq()

      assert length(generated_modules) == 2, """
      Expected two distinct generated Jido action modules (one per `jido`
      entry), got: #{inspect(generated_modules)}. See agentjido/ash_jido#19.
      """

      for module <- generated_modules do
        assert Code.ensure_loaded?(module),
               "Expected #{inspect(module)} to be compiled and loadable."

        assert function_exported?(module, :run, 2),
               "Expected #{inspect(module)} to implement Jido.Action.run/2."

        assert function_exported?(module, :name, 0),
               "Expected #{inspect(module)} to implement Jido.Action.name/0."
      end

      jido_names = Enum.map(generated_modules, & &1.name())

      assert "list_multi_items" in jido_names,
             "Expected a module with `name: \"list_multi_items\"`. Got: #{inspect(jido_names)}"

      assert "get_multi_item" in jido_names,
             "Expected a module with `name: \"get_multi_item\"`. Got: #{inspect(jido_names)}"
    end
  end

  describe "module name derivation" do
    test "uses explicit module_name for same-action variants" do
      list_module = Module.concat([MultiJidoItem, "Jido", "ListMultiItems"])
      get_module = Module.concat([MultiJidoItem, "Jido", "GetMultiItem"])
      fallback_module = Module.concat([MultiJidoItem, "Jido", "Read"])

      assert Code.ensure_loaded?(list_module), """
      Expected #{inspect(list_module)} to be generated from the explicit
      `module_name:` on the `name: "list_multi_items"` entry.
      """

      assert Code.ensure_loaded?(get_module), """
      Expected #{inspect(get_module)} to be generated from the explicit
      `module_name:` on the `name: "get_multi_item"` entry.
      """

      refute Code.ensure_loaded?(fallback_module), """
      Did not expect #{inspect(fallback_module)} to exist: no `jido` entry
      in the fixture uses the default module name.
      """

      assert list_module.name() == "list_multi_items"
      assert get_module.name() == "get_multi_item"
    end

    test "preserves Ash-action-based default module names for named singleton entries" do
      generated_modules =
        AshJido.Test.User.spark_dsl_config()
        |> Spark.Dsl.Extension.get_persisted(:generated_jido_modules)
        |> List.wrap()

      assert Code.ensure_loaded?(AshJido.Test.User.Jido.ByEmail)
      assert AshJido.Test.User.Jido.ByEmail.name() == "find_user_by_email"

      assert AshJido.Test.User.Jido.ByEmail in generated_modules
      refute AshJido.Test.User.Jido.FindUserByEmail in generated_modules
    end

    test "named entries do not collide with different Ash action default module names" do
      unique_suffix = System.unique_integer([:positive])
      module_name = Module.concat(__MODULE__, :"NamedEntryCollisionResource#{unique_suffix}")

      resource_ast =
        quote do
          defmodule unquote(module_name) do
            use Ash.Resource,
              domain: nil,
              extensions: [AshJido],
              data_layer: Ash.DataLayer.Ets

            ets do
              private?(true)
            end

            attributes do
              uuid_primary_key(:id)
              attribute(:title, :string, allow_nil?: false)
            end

            actions do
              defaults([:read])

              action :list_items do
                returns(:string)

                run(fn _input, _context ->
                  {:ok, "custom"}
                end)
              end
            end

            jido do
              action(:read, name: "list_items")
              action(:list_items)
            end
          end
        end

      Code.compile_quoted(resource_ast)

      generated_modules =
        module_name.spark_dsl_config()
        |> Spark.Dsl.Extension.get_persisted(:generated_jido_modules)
        |> List.wrap()

      assert Module.concat([module_name, "Jido", "Read"]) in generated_modules
      assert Module.concat([module_name, "Jido", "ListItems"]) in generated_modules
    end
  end

  describe "duplicate module name validation" do
    test "raises at compile time when two jido entries would produce the same module name" do
      # Two entries that resolve to the same generated module name — here,
      # neither specifies a `name:` or `module_name:`, so both fall back
      # to the Ash action name (`:read`) and collide. The transformer must
      # surface this as a compile-time error instead of silently dropping
      # one of the entries.
      unique_suffix = System.unique_integer([:positive])
      module_name = Module.concat(__MODULE__, :"DuplicateModuleNameResource#{unique_suffix}")

      resource_ast =
        quote do
          defmodule unquote(module_name) do
            use Ash.Resource,
              domain: nil,
              extensions: [AshJido],
              data_layer: Ash.DataLayer.Ets

            ets do
              private?(true)
            end

            attributes do
              uuid_primary_key(:id)
              attribute(:title, :string, allow_nil?: false)
            end

            actions do
              defaults([:read])
            end

            jido do
              action(:read, description: "First read entry")
              action(:read, description: "Second read entry")
            end
          end
        end

      error =
        assert_raise ArgumentError, fn ->
          Code.compile_quoted(resource_ast)
        end

      assert error.message =~ "AshJido: multiple `jido` entries"
      assert error.message =~ "resolve to the same generated module"
      assert error.message =~ ".Jido.Read"
      assert error.message =~ "action: :read, name: nil"
      assert error.message =~ "explicit `module_name:`"
    end
  end
end
