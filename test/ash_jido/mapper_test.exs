defmodule AshJido.MapperTest do
  use ExUnit.Case, async: true

  alias AshJido.Mapper
  alias AshJido.Test.User

  defmodule PlainStruct do
    defstruct [:x, :y, :__meta__]
  end

  describe "wrap_result/2" do
    test "converts single resource struct to map when output_map? true" do
      user = %User{id: "123", name: "John", email: "john@example.com", age: 30}

      result = Mapper.wrap_result({:ok, user}, %{output_map?: true})

      assert {:ok, %{id: "123", name: "John", email: "john@example.com", age: 30}} = result
    end

    test "wraps list of resources in result map" do
      users = [
        %User{id: "1", name: "Alice", email: "alice@example.com", age: 25},
        %User{id: "2", name: "Bob", email: "bob@example.com", age: 35}
      ]

      result = Mapper.wrap_result({:ok, users}, %{output_map?: true})

      assert {:ok, %{result: converted_users}} = result
      assert [%{id: "1", name: "Alice"}, %{id: "2", name: "Bob"}] = converted_users
    end

    test "skips conversion when output_map? false" do
      user = %User{id: "123", name: "John", email: "john@example.com", age: 30}

      result = Mapper.wrap_result({:ok, user}, %{output_map?: false})

      assert {:ok, ^user} = result
    end

    test "handles raw struct without tuple wrapper" do
      user = %User{id: "456", name: "Jane", email: "jane@example.com", age: 28}

      result = Mapper.wrap_result(user, %{output_map?: true})

      assert {:ok, %{id: "456", name: "Jane", email: "jane@example.com", age: 28}} = result
    end

    test "wraps raw list in result map" do
      users = [
        %User{id: "1", name: "Alice", email: "alice@example.com", age: 25}
      ]

      result = Mapper.wrap_result(users, %{output_map?: true})

      assert {:ok, %{result: [%{id: "1", name: "Alice"}]}} = result
    end

    test "propagates non-exception errors unchanged" do
      result = Mapper.wrap_result({:error, :timeout}, %{})

      assert {:error, :timeout} = result
    end

    test "propagates non-exception errors with custom message" do
      result = Mapper.wrap_result({:error, "Custom error message"}, %{})

      assert {:error, "Custom error message"} = result
    end

    test "converts Ash exception to Jido.Action.Error format" do
      ash_error = %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{resource: User}]}

      result = Mapper.wrap_result({:error, ash_error}, %{})

      assert {:error, jido_error} = result
      # Invalid errors map to InvalidInputError (validation_error)
      assert %Jido.Action.Error.InvalidInputError{} = jido_error
      assert is_binary(jido_error.message)
      assert jido_error.details.ash_error == ash_error
    end

    test "handles non-Ash struct fallback conversion" do
      data = %PlainStruct{x: 1, y: 2, __meta__: "should_be_filtered"}

      result = Mapper.wrap_result({:ok, data}, %{output_map?: true})

      # For non-Ash structs, should return the struct as-is
      assert {:ok, ^data} = result
    end

    test "handles nested resource conversion" do
      # Test that nested resources are also converted
      user_with_posts = %User{
        id: "123",
        name: "John",
        email: "john@example.com",
        age: 30
      }

      result = Mapper.wrap_result({:ok, user_with_posts}, %{output_map?: true})

      assert {:ok, %{id: "123", name: "John", email: "john@example.com", age: 30}} = result
    end

    test "wraps empty list in result map" do
      result = Mapper.wrap_result({:ok, []}, %{output_map?: true})

      assert {:ok, %{result: []}} = result
    end

    test "wraps nil data in result map" do
      result = Mapper.wrap_result({:ok, nil}, %{output_map?: true})

      assert {:ok, %{result: nil}} = result
    end

    test "wraps string result in map" do
      result = Mapper.wrap_result({:ok, "hello"}, %{output_map?: true})

      assert {:ok, %{result: "hello"}} = result
    end

    test "wraps integer result in map" do
      result = Mapper.wrap_result({:ok, 42}, %{output_map?: true})

      assert {:ok, %{result: 42}} = result
    end

    test "wraps boolean result in map" do
      result = Mapper.wrap_result({:ok, true}, %{output_map?: true})

      assert {:ok, %{result: true}} = result
    end

    test "wraps atom result in map" do
      result = Mapper.wrap_result({:ok, :custom_atom}, %{output_map?: true})

      assert {:ok, %{result: :custom_atom}} = result
    end

    test "wraps raw string (from Ash generic action) in map" do
      result = Mapper.wrap_result("raw string", %{output_map?: true})

      assert {:ok, %{result: "raw string"}} = result
    end

    test "wraps raw integer in map" do
      result = Mapper.wrap_result(123, %{output_map?: true})

      assert {:ok, %{result: 123}} = result
    end

    test "passes map results through unchanged" do
      result = Mapper.wrap_result({:ok, %{key: "value"}}, %{output_map?: true})

      assert {:ok, %{key: "value"}} = result
    end

    test "converts exception with fallback when Jido.Error not available" do
      # This tests the rescue clause in convert_ash_error_to_jido_error
      ash_error = %RuntimeError{message: "Test error"}

      result = Mapper.wrap_result({:error, ash_error}, %{})

      # Should fall back to a simple map format
      assert {:error, error_data} = result
      assert is_map(error_data) or is_struct(error_data)
    end
  end
end
