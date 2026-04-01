defmodule AshJido.ErrorTest do
  use ExUnit.Case, async: true

  alias AshJido.Error

  defmodule WrappedError do
    defexception [:error, message: "wrapped"]
  end

  describe "from_ash/1" do
    test "converts Ash.Error.Invalid to validation_error" do
      ash_error = %Ash.Error.Invalid{
        errors: [
          %Ash.Error.Changes.Required{field: :name, type: :attribute}
        ]
      }

      result = Error.from_ash(ash_error)

      assert %Jido.Action.Error.InvalidInputError{} = result
      assert result.message =~ "is required"
      assert result.details.ash_error == ash_error
      assert result.details.fields == %{name: ["attribute name is required"]}
    end

    test "converts Ash.Error.Forbidden to execution_error with forbidden reason" do
      ash_error = %Ash.Error.Forbidden{
        errors: [
          %Ash.Error.Forbidden.Policy{}
        ]
      }

      result = Error.from_ash(ash_error)

      assert %Jido.Action.Error.ExecutionFailureError{} = result
      assert result.details.reason == :forbidden
      assert result.details.ash_error == ash_error
    end

    test "converts Ash.Error.Framework to internal_error" do
      ash_error = %Ash.Error.Framework{
        errors: [
          %Ash.Error.Framework.InvalidReturnType{message: "invalid return"}
        ]
      }

      result = Error.from_ash(ash_error)

      assert %Jido.Action.Error.InternalError{} = result
      assert result.details.ash_error == ash_error
    end

    test "converts Ash.Error.Unknown to internal_error" do
      ash_error = %Ash.Error.Unknown{
        errors: [
          %Ash.Error.Unknown.UnknownError{error: "something went wrong"}
        ]
      }

      result = Error.from_ash(ash_error)

      assert %Jido.Action.Error.InternalError{} = result
      assert result.details.ash_error == ash_error
    end

    test "converts generic exception to execution_error" do
      ash_error = %RuntimeError{message: "runtime error"}

      result = Error.from_ash(ash_error)

      assert %Jido.Action.Error.ExecutionFailureError{} = result
      assert result.details.ash_error == ash_error
    end

    test "preserves underlying errors in details" do
      underlying = [%Ash.Error.Changes.Required{field: :email, type: :attribute}]
      ash_error = %Ash.Error.Invalid{errors: underlying}

      result = Error.from_ash(ash_error)

      assert length(result.details.underlying_errors) == 1
      assert hd(result.details.underlying_errors).__struct__ == Ash.Error.Changes.Required
    end
  end

  describe "extract_underlying_errors/1" do
    test "extracts errors list from Ash error" do
      errors = [
        %Ash.Error.Changes.Required{field: :name, type: :attribute},
        %Ash.Error.Changes.Required{field: :email, type: :attribute}
      ]

      ash_error = %Ash.Error.Invalid{errors: errors}

      result = Error.extract_underlying_errors(ash_error)

      assert length(result) == 2
    end

    test "extracts single error from error field" do
      inner_error = %Ash.Error.Changes.Required{field: :name, type: :attribute}
      ash_error = %WrappedError{error: inner_error}

      result = Error.extract_underlying_errors(ash_error)

      assert length(result) == 1
      assert hd(result) == inner_error
    end

    test "returns empty list when no errors present" do
      ash_error = %Ash.Error.Invalid{errors: []}

      result = Error.extract_underlying_errors(ash_error)

      assert result == []
    end

    test "returns empty list for exception without errors field" do
      exception = %RuntimeError{message: "test"}

      result = Error.extract_underlying_errors(exception)

      assert result == []
    end
  end

  describe "extract_field_errors/1" do
    test "extracts field errors from changeset errors" do
      ash_error = %Ash.Error.Invalid{
        errors: [
          %Ash.Error.Changes.Required{field: :name, type: :attribute},
          %Ash.Error.Changes.InvalidAttribute{field: :email, message: "is invalid"}
        ]
      }

      result = Error.extract_field_errors(ash_error)

      assert result.name == ["attribute name is required"]
      assert result.email == ["is invalid"]
    end

    test "extracts field errors from path-based errors" do
      ash_error = %Ash.Error.Invalid{
        errors: [
          %{path: [:user, :profile, :name], message: "is too short"}
        ]
      }

      result = Error.extract_field_errors(ash_error)

      assert result.name == ["is too short"]
    end

    test "groups multiple errors per field" do
      ash_error = %Ash.Error.Invalid{
        errors: [
          %Ash.Error.Changes.Required{field: :name, type: :attribute},
          %Ash.Error.Changes.InvalidAttribute{field: :name, message: "is too short"}
        ]
      }

      result = Error.extract_field_errors(ash_error)

      assert result.name == ["attribute name is required", "is too short"]
    end

    test "returns empty map for errors without field information" do
      ash_error = %Ash.Error.Invalid{
        errors: [
          %Ash.Error.Framework.InvalidReturnType{message: "invalid"}
        ]
      }

      result = Error.extract_field_errors(ash_error)

      assert result == %{}
    end
  end

  describe "extract_changeset_errors/1" do
    test "extracts changeset-related errors" do
      ash_error = %Ash.Error.Invalid{
        errors: [
          %Ash.Error.Changes.Required{field: :name, type: :attribute},
          %Ash.Error.Changes.InvalidAttribute{field: :email, message: "is invalid"},
          %Ash.Error.Framework.InvalidReturnType{message: "framework error"}
        ]
      }

      result = Error.extract_changeset_errors(ash_error)

      assert length(result) == 2

      changeset_modules = Enum.map(result, & &1.type)
      assert Ash.Error.Changes.Required in changeset_modules
      assert Ash.Error.Changes.InvalidAttribute in changeset_modules
    end

    test "extracts change-related invalid attribute errors" do
      ash_error = %Ash.Error.Invalid{
        errors: [
          %Ash.Error.Changes.InvalidAttribute{field: :age, message: "must be positive"}
        ]
      }

      result = Error.extract_changeset_errors(ash_error)

      assert length(result) == 1
      assert hd(result).type == Ash.Error.Changes.InvalidAttribute
    end

    test "includes error details in result" do
      ash_error = %Ash.Error.Invalid{
        errors: [
          %Ash.Error.Changes.Required{field: :name, type: :attribute}
        ]
      }

      result = Error.extract_changeset_errors(ash_error)

      assert hd(result).message =~ "is required"
      assert is_map(hd(result).details)
    end

    test "returns empty list when no changeset errors" do
      ash_error = %Ash.Error.Invalid{
        errors: [
          %Ash.Error.Framework.InvalidReturnType{message: "framework error"}
        ]
      }

      result = Error.extract_changeset_errors(ash_error)

      assert result == []
    end
  end

  describe "build_details/1" do
    test "builds complete details map with all error information" do
      ash_error = %Ash.Error.Invalid{
        errors: [
          %Ash.Error.Changes.Required{field: :name, type: :attribute},
          %Ash.Error.Changes.InvalidAttribute{field: :email, message: "is invalid"}
        ]
      }

      result = Error.from_ash(ash_error)

      assert result.details.ash_error == ash_error
      assert length(result.details.underlying_errors) == 2
      assert map_size(result.details.fields) == 2
      assert length(result.details.changeset_errors) == 2
    end
  end
end
