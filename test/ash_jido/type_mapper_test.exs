defmodule AshJido.TypeMapperTest do
  @moduledoc """
  Tests for AshJido.TypeMapper module.

  Tests the conversion of Ash types to NimbleOptions types,
  which is critical for generating correct parameter schemas.
  """

  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias AshJido.TypeMapper
  alias AshJido.Test.SampleExtractionResult

  describe "ash_type_to_nimble_options/2" do
    test "maps primitive scalar types correctly" do
      # String type
      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.String, %{allow_nil?: false})
      assert result[:type] == :string
      assert result[:required] == true

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.String, %{allow_nil?: true})
      assert result[:type] == :string
      refute Keyword.has_key?(result, :required)

      # Integer type
      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Integer, %{allow_nil?: false})
      assert result[:type] == :integer
      assert result[:required] == true

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Integer, %{allow_nil?: true})
      assert result[:type] == :integer
      refute Keyword.has_key?(result, :required)

      # Float type
      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Float, %{allow_nil?: false})
      assert result[:type] == :float
      assert result[:required] == true

      # Boolean type
      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Boolean, %{})
      assert result[:type] == :boolean

      # UUID type
      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.UUID, %{})
      assert result[:type] == :string
    end

    test "maps date and time types to string" do
      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Date, %{})
      assert result[:type] == :string

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.DateTime, %{})
      assert result[:type] == :string

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Time, %{})
      assert result[:type] == :string

      # UtcDateTime falls through to default case (not explicitly handled)
      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.UtcDateTime, %{})
      assert result[:type] == :any
    end

    test "maps decimal to float" do
      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Decimal, %{})
      assert result[:type] == :float

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Decimal, %{allow_nil?: false})
      assert result[:type] == :float
      assert result[:required] == true
    end

    test "maps array types recursively" do
      # Array of strings
      result = TypeMapper.ash_type_to_nimble_options({:array, Ash.Type.String}, %{})
      assert result[:type] == {:list, :string}

      # Array of integers
      result =
        TypeMapper.ash_type_to_nimble_options({:array, Ash.Type.Integer}, %{allow_nil?: false})

      assert result[:type] == {:list, :integer}
      assert result[:required] == true

      # Array of floats
      result = TypeMapper.ash_type_to_nimble_options({:array, Ash.Type.Float}, %{})
      assert result[:type] == {:list, :float}
    end

    test "unknown types fallback to any" do
      result = TypeMapper.ash_type_to_nimble_options(:unknown_type, %{})
      assert result[:type] == :any

      result = TypeMapper.ash_type_to_nimble_options(SomeCustomType, %{})
      assert result[:type] == :any
    end

    test "includes description when provided" do
      options = %{description: "User's age in years"}

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Integer, options)
      assert result[:type] == :integer
      assert result[:doc] == "User's age in years"
    end

    test "includes default when provided" do
      options = %{default: 18}

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Integer, options)
      assert result[:type] == :integer
      assert result[:default] == 18
    end

    test "combines all options correctly" do
      options = %{
        allow_nil?: false,
        description: "User's age in years",
        default: 18
      }

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Integer, options)

      assert result[:type] == :integer
      assert result[:required] == true
      assert result[:doc] == "User's age in years"
      assert result[:default] == 18
    end

    test "handles empty options map" do
      assert TypeMapper.ash_type_to_nimble_options(Ash.Type.String, %{}) ==
               [type: :string]
    end

    test "nil allow_nil? is treated as allowing nil" do
      options = %{allow_nil?: nil}

      assert TypeMapper.ash_type_to_nimble_options(Ash.Type.String, options) ==
               [type: :string]
    end

    test "converts Ash.Type.Atom with one_of constraints to {:in, string_values}" do
      options = %{type: Ash.Type.Atom, constraints: [one_of: [:a, :b, :c]]}

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Atom, options)
      assert result[:type] == {:in, ["a", "b", "c"]}
    end

    test "leaves Ash.Type.Atom as :atom when no one_of constraint" do
      options = %{type: Ash.Type.Atom, constraints: []}

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Atom, options)
      assert result[:type] == :atom
    end
  end

  describe "edge cases and complex scenarios" do
    test "nested array types" do
      # This tests how we handle complex nested structures
      nested_array = {:array, {:array, Ash.Type.String}}

      result = TypeMapper.ash_type_to_nimble_options(nested_array, %{})

      # Should handle nested arrays gracefully
      assert result[:type] == {:list, {:list, :string}}
    end

    test "all option combinations" do
      options = %{
        allow_nil?: false,
        description: "Complex field",
        default: "default_value"
      }

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.String, options)

      # Should include all provided options
      assert Keyword.get(result, :type) == :string
      assert Keyword.get(result, :required) == true
      assert Keyword.get(result, :doc) == "Complex field"
      assert Keyword.get(result, :default) == "default_value"
    end
  end

  describe "typed_struct_to_schema/1" do
    test "converts TypedStruct module to NimbleOptions schema" do
      schema = TypeMapper.typed_struct_to_schema(SampleExtractionResult)

      assert is_list(schema)
      assert Keyword.keyword?(schema)

      # Check that all expected fields are present
      assert Keyword.has_key?(schema, :name)
      assert Keyword.has_key?(schema, :age)
      assert Keyword.has_key?(schema, :active)
      assert Keyword.has_key?(schema, :score)
      assert Keyword.has_key?(schema, :category)
      assert Keyword.has_key?(schema, :tags)
      assert Keyword.has_key?(schema, :start_date)
    end

    test "preserves field types correctly" do
      schema = TypeMapper.typed_struct_to_schema(SampleExtractionResult)

      assert schema[:name][:type] == :string
      assert schema[:age][:type] == :integer
      assert schema[:active][:type] == :boolean
      assert schema[:score][:type] == :float
      assert schema[:start_date][:type] == :string
    end

    test "preserves array types" do
      schema = TypeMapper.typed_struct_to_schema(SampleExtractionResult)

      assert schema[:tags][:type] == {:list, :string}
    end

    test "sets required: true for fields with allow_nil?: false" do
      schema = TypeMapper.typed_struct_to_schema(SampleExtractionResult)

      assert schema[:name][:required] == true
      assert schema[:category][:required] == true
    end

    test "omits required key for optional fields" do
      schema = TypeMapper.typed_struct_to_schema(SampleExtractionResult)

      refute Keyword.has_key?(schema[:age], :required)
      refute Keyword.has_key?(schema[:active], :required)
      refute Keyword.has_key?(schema[:score], :required)
      refute Keyword.has_key?(schema[:tags], :required)
    end

    test "preserves field descriptions as doc" do
      schema = TypeMapper.typed_struct_to_schema(SampleExtractionResult)

      assert schema[:name][:doc] == "The name"
      assert schema[:age][:doc] == "The age"
      assert schema[:score][:doc] == "Score value"
      assert schema[:category][:doc] == "The category"
      assert schema[:tags][:doc] == "List of tags"
      assert schema[:start_date][:doc] == "Start date"
    end

    test "converts atom one_of constraints to {:in, values}" do
      schema = TypeMapper.typed_struct_to_schema(SampleExtractionResult)

      # Atom field with one_of constraint should be converted to {:in, string_values}
      assert schema[:category][:type] == {:in, ["a", "b", "c"]}
    end

    test "handles fields without descriptions" do
      schema = TypeMapper.typed_struct_to_schema(SampleExtractionResult)

      # active field has no description
      refute Keyword.has_key?(schema[:active], :doc)
    end
  end
end
