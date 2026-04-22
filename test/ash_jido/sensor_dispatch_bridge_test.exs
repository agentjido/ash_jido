defmodule AshJido.SensorDispatchBridgeTest do
  use ExUnit.Case, async: true

  alias AshJido.SensorDispatchBridge

  defmodule EchoSensor do
    use Jido.Sensor,
      name: "echo_sensor",
      description: "Emits any forwarded signal back to the configured agent ref",
      schema: Zoi.object(%{}, coerce: true)

    @impl true
    def init(_config, _context), do: {:ok, %{}}

    @impl true
    def handle_event(%Jido.Signal{} = signal, state), do: {:ok, state, [{:emit, signal}]}

    def handle_event(_event, state), do: {:ok, state}
  end

  describe "forward/2" do
    test "returns error when runtime is not available (dead pid)" do
      # Create a process and kill it
      pid = spawn(fn -> nil end)
      # Ensure process dies
      Process.sleep(10)

      assert {:error, :runtime_unavailable} = SensorDispatchBridge.forward({:signal, nil}, pid)
    end

    test "returns error when named process is not registered" do
      assert {:error, :runtime_unavailable} =
               SensorDispatchBridge.forward({:signal, nil}, :nonexistent_runtime)
    end

    test "returns error for invalid signal message format" do
      pid = start_sensor_runtime(self())

      assert {:error, :invalid_signal_message} =
               SensorDispatchBridge.forward({:invalid, nil}, pid)
    end

    test "successfully forwards signal to runtime" do
      parent = self()
      pid = start_sensor_runtime(parent)

      {:ok, signal} = Jido.Signal.new("test.signal", %{data: "value"})

      assert :ok = SensorDispatchBridge.forward(signal, pid)
      assert_receive {:signal, ^signal}, 500
    end

    test "successfully forwards signal wrapped in tuple" do
      parent = self()
      pid = start_sensor_runtime(parent)

      {:ok, signal} = Jido.Signal.new("test.signal", %{data: "value"})

      assert :ok = SensorDispatchBridge.forward({:signal, signal}, pid)
      assert_receive {:signal, ^signal}, 500
    end

    test "successfully forwards signal wrapped in ok tuple" do
      parent = self()
      pid = start_sensor_runtime(parent)

      {:ok, signal} = Jido.Signal.new("test.signal", %{data: "value"})

      assert :ok = SensorDispatchBridge.forward({:signal, {:ok, signal}}, pid)
      assert_receive {:signal, ^signal}, 500
    end
  end

  describe "forward_many/2" do
    test "forwards multiple signals and counts successes" do
      parent = self()
      pid = start_sensor_runtime(parent)

      {:ok, signal1} = Jido.Signal.new("test.signal1", %{id: 1})
      {:ok, signal2} = Jido.Signal.new("test.signal2", %{id: 2})
      {:ok, signal3} = Jido.Signal.new("test.signal3", %{id: 3})

      messages = [
        signal1,
        {:signal, signal2},
        {:signal, {:ok, signal3}}
      ]

      result = SensorDispatchBridge.forward_many(messages, pid)

      assert result.forwarded == 3
      assert result.errors == []

      assert_receive {:signal, ^signal1}, 500
      assert_receive {:signal, ^signal2}, 500
      assert_receive {:signal, ^signal3}, 500
    end

    test "tracks errors for invalid signals" do
      parent = self()
      pid = start_sensor_runtime(parent)

      {:ok, signal} = Jido.Signal.new("test.signal", %{})
      invalid_message = {:invalid, "format"}

      messages = [signal, invalid_message]

      result = SensorDispatchBridge.forward_many(messages, pid)

      assert result.forwarded == 1
      assert length(result.errors) == 1
      assert hd(result.errors).reason == :invalid_signal_message
      assert hd(result.errors).message == invalid_message
    end

    test "tracks errors for unavailable runtime" do
      dead_pid = spawn(fn -> nil end)
      Process.sleep(10)

      {:ok, signal} = Jido.Signal.new("test.signal", %{})

      result = SensorDispatchBridge.forward_many([signal], dead_pid)

      assert result.forwarded == 0
      assert length(result.errors) == 1
      assert hd(result.errors).reason == :runtime_unavailable
    end

    test "returns empty result for empty list" do
      pid = start_sensor_runtime(self())

      result = SensorDispatchBridge.forward_many([], pid)

      assert result.forwarded == 0
      assert result.errors == []
    end
  end

  describe "forward_or_ignore/2" do
    test "returns :ok on successful forward" do
      parent = self()
      pid = start_sensor_runtime(parent)

      {:ok, signal} = Jido.Signal.new("test.signal", %{})

      assert :ok = SensorDispatchBridge.forward_or_ignore(signal, pid)
    end

    test "returns :ignored for invalid signal message" do
      pid = start_sensor_runtime(self())

      assert :ignored = SensorDispatchBridge.forward_or_ignore({:invalid, nil}, pid)
    end

    test "returns error for unavailable runtime" do
      dead_pid = spawn(fn -> nil end)
      Process.sleep(10)

      {:ok, signal} = Jido.Signal.new("test.signal", %{})

      assert {:error, :runtime_unavailable} =
               SensorDispatchBridge.forward_or_ignore(signal, dead_pid)
    end
  end

  defp start_sensor_runtime(agent_ref) do
    start_supervised!({Jido.Sensor.Runtime, sensor: EchoSensor, config: %{}, context: %{agent_ref: agent_ref}})
  end
end
