defmodule AshJido.State.Projection do
  @moduledoc false

  alias Ash.Resource.Info
  alias Jido.Codec.Term

  @doc false
  @spec check(term(), module(), atom(), module() | nil, keyword()) :: :ok | {:error, String.t()}
  def check(value, resource, field, codec, _options) do
    with true <- safe_value?(value),
         {:ok, decoded} <- decode(codec, value),
         :ok <- validate(Info.attribute(resource, field), decoded) do
      :ok
    else
      _ -> {:error, "value does not satisfy the Ash field type and constraints"}
    end
  end

  @doc false
  @spec from_record(struct(), map()) :: {:ok, map()} | {:error, term()}
  def from_record(record, descriptor) do
    Map.new(descriptor.fields, &{&1, Map.get(descriptor.codecs, &1)})
    |> Enum.reduce_while({:ok, %{}}, fn {field, codec}, {:ok, projection} ->
      with {:ok, value} <- Map.fetch(record, field),
           true <- available?(value),
           {:ok, encoded} <- encode(codec, value),
           true <- safe_value?(encoded) do
        {:cont, {:ok, Map.put(projection, field, encoded)}}
      else
        _ -> {:halt, {:error, {:ash_state_field_unavailable, field}}}
      end
    end)
  end

  @doc false
  @spec changes(map(), map(), map()) :: {:ok, map(), map()} | {:error, term()}
  def changes(before, candidate, descriptor) do
    read_only = descriptor.fields -- descriptor.writable

    if Enum.any?(read_only, &(Map.fetch!(before, &1) !== Map.fetch!(candidate, &1))) do
      {:error, :ash_state_read_only}
    else
      changed =
        Enum.reject(descriptor.writable, fn field ->
          attribute = Info.attribute(descriptor.resource, field)
          equal?(Map.fetch!(before, field), Map.fetch!(candidate, field), attribute, descriptor.codecs[field])
        end)

      with {:ok, changes} <- inputs(changed, candidate, descriptor),
           {:ok, fields} <- inputs(Map.values(descriptor.arguments), candidate, descriptor) do
        arguments = Map.new(descriptor.arguments, fn {arg, field} -> {arg, Map.fetch!(fields, field)} end)
        {:ok, changes, arguments}
      end
    end
  end

  @doc false
  @spec verify_writable(map(), map(), map()) :: :ok | {:error, term()}
  def verify_writable(candidate, canonical, descriptor) do
    case Enum.find(descriptor.writable, &(Map.fetch!(candidate, &1) !== Map.fetch!(canonical, &1))) do
      nil -> :ok
      field -> {:error, {:ash_state_writable_field_changed, field}}
    end
  end

  defp inputs(fields, state, descriptor) do
    Enum.reduce_while(fields, {:ok, %{}}, fn field, {:ok, values} ->
      case decode(Map.get(descriptor.codecs, field), Map.fetch!(state, field)) do
        {:ok, value} -> {:cont, {:ok, Map.put(values, field, value)}}
        _ -> {:halt, {:error, {:invalid_ash_state_field, field}}}
      end
    end)
  end

  defp validate(nil, _value), do: :ok
  defp validate(%{allow_nil?: true}, nil), do: :ok
  defp validate(_attribute, nil), do: :error

  defp validate(%{allow_nil?: allow_nil?, type: type, constraints: constraints}, value) do
    with {:ok, cast} <- Ash.Type.cast_input(type, value, constraints),
         {:ok, value} <- Ash.Type.apply_constraints(type, cast, constraints),
         true <- allow_nil? or not is_nil(value),
         do: :ok
  end

  defp equal?(left, right, _attribute, _codec) when left === right, do: true

  defp equal?(left, right, %{type: type, constraints: constraints}, codec) do
    with {:ok, left} <- cast(type, constraints, codec, left),
         {:ok, right} <- cast(type, constraints, codec, right) do
      Ash.Type.equal?(type, left, right, constraints)
    else
      _ -> false
    end
  end

  defp cast(type, constraints, codec, value) do
    with {:ok, value} <- decode(codec, value),
         do: Ash.Type.cast_input(type, value, constraints)
  end

  defp available?(%Ash.NotLoaded{}), do: false
  defp available?(%Ash.ForbiddenField{}), do: false
  defp available?(_), do: true

  defp safe_value?(value), do: Term.valid?(value) and visible?(value)

  defp visible?(%Ash.NotLoaded{}), do: false
  defp visible?(%Ash.ForbiddenField{}), do: false
  defp visible?(%{__metadata__: _ash_record_metadata}), do: false

  defp visible?(value) when is_map(value),
    do: Enum.all?(Map.to_list(value), fn {key, item} -> visible?(key) and visible?(item) end)

  defp visible?(value) when is_list(value), do: Enum.all?(value, &visible?/1)
  defp visible?(value) when is_tuple(value), do: value |> Tuple.to_list() |> visible?()
  defp visible?(_value), do: true

  defp encode(nil, value), do: {:ok, value}
  defp encode(codec, value), do: codec.encode(value)

  defp decode(nil, value), do: {:ok, value}
  defp decode(codec, value), do: codec.decode(value)
end
