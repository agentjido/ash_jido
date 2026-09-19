defmodule AshJido.Error do
  @moduledoc """
  Converts Ash failures into a small, redacted Jido Action error surface.
  """

  alias Jido.Action.Error

  @doc "Converts an Ash error without exposing Ash internal values."
  @spec from_ash(term()) :: Exception.t()
  def from_ash(error) do
    case category(error) do
      :invalid_input ->
        Error.validation_error("Ash action input is invalid", %{
          reason: :invalid_input,
          fields: extract_field_errors(error)
        })

      :not_found ->
        Error.execution_error("Ash record was not found", %{reason: :not_found})

      :forbidden ->
        Error.execution_error("Ash action is forbidden", %{reason: :forbidden})

      :conflict ->
        Error.execution_error("Ash action has a conflict", %{reason: :conflict})

      :timeout ->
        Error.timeout_error("Ash action timed out", %{reason: :timeout})

      :internal ->
        Error.internal_error("Ash action failed", %{reason: :internal})
    end
  end

  @doc false
  @spec internal(atom(), term()) :: Exception.t()
  def internal(_kind, _reason) do
    Error.internal_error("Ash action failed", %{reason: :internal})
  end

  @doc "Returns the safe field validation messages in an Ash error."
  @spec extract_field_errors(term()) :: %{optional(atom()) => [String.t()]}
  def extract_field_errors(error) do
    error
    |> underlying_errors()
    |> Enum.flat_map(fn nested ->
      case field_name(nested) do
        nil -> []
        field -> [{field, safe_message(nested)}]
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc false
  @spec extract_underlying_errors(term()) :: [term()]
  def extract_underlying_errors(error), do: underlying_errors(error)

  defp category(%Ash.Error.Forbidden{}), do: :forbidden
  defp category(%Ash.Error.Invalid{} = error), do: nested_category(error, :invalid_input)
  defp category(%Ash.Error.Framework{}), do: :internal
  defp category(%Ash.Error.Unknown{} = error), do: nested_category(error, :internal)

  defp category(error) do
    module_category(error) || :internal
  end

  defp nested_category(error, default) do
    error
    |> underlying_errors()
    |> Enum.find_value(&module_category/1)
    |> Kernel.||(default)
  end

  defp module_category(%{__struct__: module}) do
    name = inspect(module)

    cond do
      String.contains?(name, "Forbidden") -> :forbidden
      String.contains?(name, "NotFound") -> :not_found
      String.contains?(name, "Stale") -> :conflict
      String.contains?(name, "Conflict") -> :conflict
      String.contains?(name, "Timeout") -> :timeout
      String.contains?(name, "Invalid") -> :invalid_input
      true -> nil
    end
  end

  defp module_category(_error), do: nil

  defp underlying_errors(%{errors: errors}) when is_list(errors) and errors != [] do
    Enum.flat_map(errors, fn error -> [error | underlying_errors(error)] end)
  end

  defp underlying_errors(%{error: error}) when not is_nil(error) do
    [error | underlying_errors(error)]
  end

  defp underlying_errors(_error), do: []

  defp field_name(%{field: field}) when is_atom(field) and not is_nil(field), do: field
  defp field_name(%{path: path}) when is_list(path) and path != [], do: List.last(path)
  defp field_name(_error), do: nil

  defp safe_message(%{message: message}) when is_binary(message) and message != "", do: message
  defp safe_message(_error), do: "is invalid"
end
