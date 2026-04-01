defmodule AshJido.Error do
  @moduledoc """
  Facade for converting Ash errors to Jido.Action.Error Splode-based errors.

  This module provides utilities to transform Ash Framework error types into
  the Jido Action error system, preserving error details and providing
  consistent error handling across the Ash-Jido integration.
  """

  alias Jido.Action.Error

  @doc """
  Converts an Ash error to a Jido.Action.Error.

  Pattern matches on different Ash error types and converts them to appropriate
  Jido error constructors:

  - `Ash.Error.Invalid` → validation_error
  - `Ash.Error.Forbidden` → execution_error with reason :forbidden
  - `Ash.Error.Framework` → internal_error
  - `Ash.Error.Unknown` → internal_error
  - Other exceptions → execution_error

  The original Ash error is preserved in the details map under the `:ash_error` key.

  ## Examples

      iex> AshJido.Error.from_ash(%Ash.Error.Invalid{errors: []})
      %Jido.Action.Error.InvalidInputError{...}

      iex> AshJido.Error.from_ash(%Ash.Error.Forbidden{errors: []})
      %Jido.Action.Error.ExecutionFailureError{...}
  """
  @spec from_ash(Exception.t()) :: Exception.t()
  def from_ash(%Ash.Error.Invalid{} = ash_error) do
    details = build_details(ash_error)
    Error.validation_error(Exception.message(ash_error), details)
  end

  def from_ash(%Ash.Error.Forbidden{} = ash_error) do
    details = build_details(ash_error) |> Map.put(:reason, :forbidden)
    Error.execution_error(Exception.message(ash_error), details)
  end

  def from_ash(%Ash.Error.Framework{} = ash_error) do
    details = build_details(ash_error)
    Error.internal_error(Exception.message(ash_error), details)
  end

  def from_ash(%Ash.Error.Unknown{} = ash_error) do
    details = build_details(ash_error)
    Error.internal_error(Exception.message(ash_error), details)
  end

  def from_ash(ash_error) when is_exception(ash_error) do
    details = build_details(ash_error)
    Error.execution_error(Exception.message(ash_error), details)
  end

  @doc """
  Extracts the list of underlying errors from an Ash error.

  Ash errors often wrap multiple underlying errors. This function
  extracts them for detailed error inspection.
  """
  @spec extract_underlying_errors(Exception.t()) :: [Exception.t()]
  def extract_underlying_errors(ash_error) do
    cond do
      Map.has_key?(ash_error, :errors) and is_list(ash_error.errors) and ash_error.errors != [] ->
        ash_error.errors

      Map.has_key?(ash_error, :error) ->
        [ash_error.error]

      true ->
        []
    end
  end

  @doc """
  Extracts field-specific errors for validation feedback.

  Returns a map where keys are field names and values are lists of
  error messages for that field.
  """
  @spec extract_field_errors(Exception.t()) :: %{atom() => [String.t()]}
  def extract_field_errors(ash_error) do
    ash_error
    |> extract_underlying_errors()
    |> Enum.flat_map(fn error ->
      case error do
        %{field: field} when not is_nil(field) ->
          [{field, error_message(error)}]

        %{path: path} when is_list(path) and length(path) > 0 ->
          field = List.last(path)
          [{field, error_message(error)}]

        _ ->
          []
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc """
  Extracts changeset-specific error information.

  Returns a list of maps containing error type, message, and details
  for errors related to changesets or validations.
  """
  @spec extract_changeset_errors(Exception.t()) :: [map()]
  def extract_changeset_errors(ash_error) do
    ash_error
    |> extract_underlying_errors()
    |> Enum.filter(fn error ->
      case error do
        %{__struct__: module} ->
          change_or_validation_error_module?(module)

        _ ->
          false
      end
    end)
    |> Enum.map(fn error ->
      %{
        type: error.__struct__,
        message: Exception.message(error),
        details: Map.from_struct(error)
      }
    end)
  end

  defp build_details(ash_error) do
    underlying_errors = extract_underlying_errors(ash_error)

    %{
      ash_error: ash_error,
      underlying_errors: underlying_errors,
      fields: extract_field_errors(ash_error),
      changeset_errors: extract_changeset_errors(ash_error)
    }
  end

  defp error_message(%{message: message}) when is_binary(message) and message != "", do: message
  defp error_message(error) when is_exception(error), do: Exception.message(error)
  defp error_message(error), do: inspect(error)

  defp change_or_validation_error_module?(module) when is_atom(module) do
    case Module.split(module) do
      ["Ash", "Error", namespace | _]
      when namespace in ["Changes", "Changeset", "Validation"] ->
        true

      _ ->
        false
    end
  end
end
