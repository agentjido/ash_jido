defmodule AshJido.SensorDispatchBridge do
  @moduledoc """
  Helper for forwarding dispatched signals to a `Jido.Sensor.Runtime` process.
  """

  @type forward_error :: :invalid_signal_message | :runtime_unavailable

  @type forward_many_result :: %{
          forwarded: non_neg_integer(),
          errors: [%{message: term(), reason: forward_error()}]
        }

  @spec forward(term(), Jido.Sensor.Runtime.server()) :: :ok | {:error, forward_error()}
  def forward(message, sensor_runtime) do
    with :ok <- ensure_runtime_available(sensor_runtime),
         {:ok, signal} <- extract_signal(message) do
      Jido.Sensor.Runtime.event(sensor_runtime, signal)
    end
  end

  @spec forward_many([term()], Jido.Sensor.Runtime.server()) :: forward_many_result()
  def forward_many(messages, sensor_runtime) when is_list(messages) do
    messages
    |> Enum.reduce(%{forwarded: 0, errors: []}, fn message, acc ->
      case forward(message, sensor_runtime) do
        :ok ->
          %{acc | forwarded: acc.forwarded + 1}

        {:error, reason} ->
          error = %{message: message, reason: reason}
          %{acc | errors: [error | acc.errors]}
      end
    end)
    |> Map.update!(:errors, &Enum.reverse/1)
  end

  @spec forward_or_ignore(term(), Jido.Sensor.Runtime.server()) ::
          :ok | :ignored | {:error, :runtime_unavailable}
  def forward_or_ignore(message, sensor_runtime) do
    case forward(message, sensor_runtime) do
      :ok -> :ok
      {:error, :invalid_signal_message} -> :ignored
      {:error, :runtime_unavailable} = error -> error
    end
  end

  defp extract_signal(%Jido.Signal{} = signal), do: {:ok, signal}
  defp extract_signal({:signal, %Jido.Signal{} = signal}), do: {:ok, signal}
  defp extract_signal({:signal, {:ok, %Jido.Signal{} = signal}}), do: {:ok, signal}
  defp extract_signal(_), do: {:error, :invalid_signal_message}

  defp ensure_runtime_available(sensor_runtime) when is_pid(sensor_runtime) do
    if Process.alive?(sensor_runtime), do: :ok, else: {:error, :runtime_unavailable}
  end

  defp ensure_runtime_available(sensor_runtime) when is_atom(sensor_runtime) do
    case Process.whereis(sensor_runtime) do
      pid when is_pid(pid) ->
        if Process.alive?(pid), do: :ok, else: {:error, :runtime_unavailable}

      _ ->
        {:error, :runtime_unavailable}
    end
  end

  defp ensure_runtime_available(_sensor_runtime), do: :ok
end
