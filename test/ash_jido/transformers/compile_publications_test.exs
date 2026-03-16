defmodule AshJido.Resource.Transformers.CompilePublicationsTest do
  use ExUnit.Case, async: true

  describe "compiled publication introspection" do
    test "persists explicit and expanded publish configs" do
      assert {:ok, publications} = AshJido.Info.publications(AshJido.Test.ReactiveResource)
      assert length(publications) == 6

      explicit = Enum.find(publications, &(&1.signal_type == "test.resource.created"))
      assert explicit.actions == [:create]
      assert explicit.include == [:id, :name, :status]

      expanded_update =
        Enum.find(publications, fn publication ->
          publication.actions == [:internal_update] and publication.signal_type == nil
        end)

      assert expanded_update.include == :changes_only
      assert expanded_update.metadata == []
    end

    test "reads signal_bus and signal_prefix config" do
      assert {:ok, :ash_jido_test_bus} = AshJido.Info.signal_bus(AshJido.Test.ReactiveResource)
      assert {:ok, "test"} = AshJido.Info.signal_prefix(AshJido.Test.ReactiveResource)
    end
  end

  describe "publish validation" do
    test "raises when publish references missing action" do
      module_name =
        "Elixir.AshJido.Test.InvalidPublicationResource#{System.unique_integer([:positive])}"

      source = """
      defmodule #{module_name} do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshJido]

        ets do
          private?(true)
        end

        attributes do
          uuid_primary_key(:id)
        end

        actions do
          defaults([:read])
        end

        jido do
          publish(:missing_action)
        end
      end
      """

      assert_raise Spark.Error.DslError, ~r/does not exist/, fn ->
        Code.compile_string(source)
      end
    end
  end
end
