defmodule AshJido.ErrorTest do
  use ExUnit.Case, async: true

  defmodule NotFoundFailure do
    defexception message: "private not found detail"
  end

  defmodule StaleFailure do
    defexception message: "private stale detail"
  end

  defmodule TimeoutFailure do
    defexception message: "private timeout detail"
  end

  defmodule InvalidFailure do
    defexception [:message, :field, :path]
  end

  defmodule ForbiddenFailure do
    defexception message: "private forbidden detail"
  end

  defmodule ConflictFailure do
    defexception message: "private conflict detail"
  end

  defmodule OtherFailure do
    defexception message: "private internal detail"
  end

  test "maps known error categories to redacted Jido errors" do
    assert %Jido.Action.Error.ExecutionFailureError{
             message: "Ash record was not found",
             details: %{reason: :not_found}
           } = AshJido.Error.from_ash(%NotFoundFailure{})

    assert %Jido.Action.Error.ExecutionFailureError{
             message: "Ash action has a conflict",
             details: %{reason: :conflict}
           } = AshJido.Error.from_ash(%StaleFailure{})

    assert %Jido.Action.Error.TimeoutError{
             message: "Ash action timed out",
             details: %{reason: :timeout}
           } = AshJido.Error.from_ash(%TimeoutFailure{})

    assert %Jido.Action.Error.InternalError{
             message: "Ash action failed",
             details: %{reason: :internal}
           } = AshJido.Error.from_ash(%OtherFailure{})

    assert %Jido.Action.Error.ExecutionFailureError{details: %{reason: :forbidden}} =
             AshJido.Error.from_ash(%ForbiddenFailure{})

    assert %Jido.Action.Error.ExecutionFailureError{details: %{reason: :conflict}} =
             AshJido.Error.from_ash(%ConflictFailure{})

    assert %Jido.Action.Error.InvalidInputError{details: %{reason: :invalid_input}} =
             AshJido.Error.from_ash(%InvalidFailure{field: :name, message: "is invalid"})

    assert %Jido.Action.Error.InternalError{details: %{reason: :internal}} =
             AshJido.Error.from_ash(:unknown)
  end

  test "collects safe field messages from nested errors" do
    error = %{
      errors: [
        %InvalidFailure{field: :email, message: "is required"},
        %{error: %InvalidFailure{path: [:profile, :name], message: nil}},
        %OtherFailure{}
      ]
    }

    assert AshJido.Error.extract_field_errors(error) == %{
             email: ["is required"],
             name: ["is invalid"]
           }

    assert [_email, _wrapper, _name, _other] = AshJido.Error.extract_underlying_errors(error)
  end

  test "uses fixed internal error data" do
    assert %Jido.Action.Error.InternalError{details: %{reason: :internal}} =
             AshJido.Error.internal(:throw, {:secret, "value"})
  end
end
