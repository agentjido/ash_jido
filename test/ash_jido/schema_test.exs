defmodule AshJido.SchemaTest do
  use ExUnit.Case, async: true

  alias AshJido.Resource.JidoAction
  alias AshJido.Schema
  alias Spark.Dsl.Transformer

  @moduletag :capture_log

  defmodule Resource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      attribute(:slug, :string, primary_key?: true, allow_nil?: false)
      attribute(:public_name, :string, allow_nil?: false, public?: true)
      attribute(:internal_code, :string, public?: false)
    end

    actions do
      create :create do
        accept([:public_name, :internal_code])

        argument(:public_reason, :string, allow_nil?: false, public?: true)
        argument(:internal_reason, :string, public?: false)
      end

      read :by_name do
        argument(:public_name, :string, allow_nil?: false, public?: true)
      end

      update :rename do
        accept([:public_name, :internal_code])
      end
    end
  end

  describe "build_parameter_schema/3" do
    test "filters private accepted attributes and arguments by default" do
      schema =
        Schema.build_parameter_schema(
          ash_action(:create),
          %JidoAction{action: :create},
          dsl_state()
        )

      assert Keyword.has_key?(schema, :public_name)
      assert Keyword.has_key?(schema, :public_reason)
      refute Keyword.has_key?(schema, :internal_code)
      refute Keyword.has_key?(schema, :internal_reason)
    end

    test "includes private inputs when explicitly configured" do
      schema =
        Schema.build_parameter_schema(
          ash_action(:create),
          %JidoAction{action: :create, include_private?: true},
          dsl_state()
        )

      assert Keyword.has_key?(schema, :internal_code)
      assert Keyword.has_key?(schema, :internal_reason)
    end

    test "adds primary key schema for update actions" do
      schema =
        Schema.build_parameter_schema(
          ash_action(:rename),
          %JidoAction{action: :rename},
          dsl_state()
        )

      assert schema[:slug][:required] == true
      assert schema[:slug][:doc] == "Primary key field slug of record to update"
    end

    test "adds query parameter schema for read actions when enabled" do
      schema =
        Schema.build_parameter_schema(
          ash_action(:by_name),
          %JidoAction{action: :by_name, query_params?: true, max_page_size: 10},
          dsl_state()
        )

      assert Keyword.has_key?(schema, :public_name)
      assert schema[:limit][:doc] =~ "Maximum: 10."
      assert schema[:filter][:type] == :any
      refute Keyword.has_key?(schema, :load)
    end

    test "adds dynamic load schema only when read allowed_loads are configured" do
      schema =
        Schema.build_parameter_schema(
          ash_action(:by_name),
          %JidoAction{action: :by_name, query_params?: true, allowed_loads: [:profile]},
          dsl_state()
        )

      assert schema[:load][:type] == :any
    end
  end

  describe "primary_key_fields/1" do
    test "returns resource primary key field names" do
      assert Schema.primary_key_fields(dsl_state()) == [:slug]
    end
  end

  defp dsl_state, do: Resource.spark_dsl_config()

  defp ash_action(name) do
    dsl_state()
    |> Transformer.get_entities([:actions])
    |> Enum.find(&(&1.name == name))
  end
end
