defmodule AshJido.SensorDispatchBridge do
  @moduledoc """
  Helper for forwarding dispatched signals to a `Jido.Sensor.Runtime` process.
  """

  @spec forward(term(), Jido.Sensor.Runtime.server()) :: :ok | {:error, :invalid_signal_message}
  def forward({:signal, %Jido.Signal{} = signal}, sensor_runtime) do
    Jido.Sensor.Runtime.event(sensor_runtime, signal)
  end

  def forward(_message, _sensor_runtime), do: {:error, :invalid_signal_message}
end
