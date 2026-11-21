defmodule AshJido.State.Identity do
  @moduledoc false

  alias Ash.Resource.Info

  @prefix "ash-row:v1:"
  @max_id_bytes 4096

  def encode(descriptor, key, tenant) when is_binary(tenant) or is_nil(tenant) do
    with {:ok, key} <- cast_key(descriptor, key),
         bytes = :erlang.term_to_binary({descriptor.resource, key, tenant}, [:deterministic]),
         true <- byte_size(bytes) <= @max_id_bytes do
      {:ok, @prefix <> Base.url_encode64(bytes, padding: false)}
    else
      _ -> {:error, :invalid_ash_state_identity}
    end
  end

  def encode(_descriptor, _key, _tenant), do: {:error, :invalid_ash_state_identity}

  def decode(descriptor, @prefix <> encoded = id) when byte_size(encoded) <= @max_id_bytes * 2 do
    with {:ok, bytes} <- Base.url_decode64(encoded, padding: false),
         true <- byte_size(bytes) <= @max_id_bytes,
         {resource, key, tenant} <- decode_term(bytes),
         true <- resource == descriptor.resource,
         {:ok, ^id} <- encode(descriptor, key, tenant) do
      {:ok, key, tenant}
    else
      _ -> {:error, :invalid_ash_state_identity}
    end
  end

  def decode(_descriptor, _id), do: {:error, :invalid_ash_state_identity}

  defp decode_term(<<131, 80, _rest::binary>>), do: :error

  defp decode_term(bytes) do
    :erlang.binary_to_term(bytes, [:safe])
  rescue
    ArgumentError -> :error
  end

  defp cast_key(%{key: [name]} = descriptor, key) when not is_map(key), do: cast_key(descriptor, %{name => key})

  defp cast_key(%{key: names, resource: resource}, key) when is_map(key) and map_size(key) == length(names) do
    Enum.reduce_while(names, {:ok, %{}}, fn name, {:ok, canonical} ->
      %{type: type, constraints: constraints} = Info.attribute(resource, name)

      with {:ok, input} <- Map.fetch(key, name),
           {:ok, cast} when not is_nil(cast) <- Ash.Type.cast_input(type, input, constraints),
           {:ok, value} when is_binary(value) or is_integer(value) or (is_atom(value) and not is_nil(value)) <-
             Ash.Type.apply_constraints(type, cast, constraints) do
        {:cont, {:ok, Map.put(canonical, name, value)}}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  defp cast_key(_descriptor, _key), do: :error
end
