defmodule AshJido.SensorDispatchBridgeTest do
  use ExUnit.Case, async: true

  alias AshJido.SensorDispatchBridge

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
      # Start a mock runtime
      pid = spawn(fn -> receive_loop() end)

      assert {:error, :invalid_signal_message} =
               SensorDispatchBridge.forward({:invalid, nil}, pid)
    end

    test "successfully forwards signal to runtime" do
      # Start a mock runtime that accepts signals
      parent = self()
      pid = spawn(fn -> signal_receiver_loop(parent) end)

      signal = Jido.Signal.new("test.signal", %{data: "value"})

      assert :ok = SensorDispatchBridge.forward(signal, pid)
      assert_receive {:signal_received, ^signal}, 500
    end

    test "successfully forwards signal wrapped in tuple" do
      parent = self()
      pid = spawn(fn -> signal_receiver_loop(parent) end)

      signal = Jido.Signal.new("test.signal", %{data: "value"})

      assert :ok = SensorDispatchBridge.forward({:signal, signal}, pid)
      assert_receive {:signal_received, ^signal}, 500
    end

    test "successfully forwards signal wrapped in ok tuple" do
      parent = self()
      pid = spawn(fn -> signal_receiver_loop(parent) end)

      signal = Jido.Signal.new("test.signal", %{data: "value"})

      assert :ok = SensorDispatchBridge.forward({:signal, {:ok, signal}}, pid)
      assert_receive {:signal_received, ^signal}, 500
    end
  end

  describe "forward_many/2" do
    test "forwards multiple signals and counts successes" do
      parent = self()
      pid = spawn(fn -> signal_receiver_loop(parent) end)

      signal1 = Jido.Signal.new("test.signal1", %{id: 1})
      signal2 = Jido.Signal.new("test.signal2", %{id: 2})
      signal3 = Jido.Signal.new("test.signal3", %{id: 3})

      messages = [
        signal1,
        {:signal, signal2},
        {:signal, {:ok, signal3}}
      ]

      result = SensorDispatchBridge.forward_many(messages, pid)

      assert result.forwarded == 3
      assert result.errors == []

      assert_receive {:signal_received, ^signal1}, 500
      assert_receive {:signal_received, ^signal2}, 500
      assert_receive {:signal_received, ^signal3}, 500
    end

    test "tracks errors for invalid signals" do
      parent = self()
      pid = spawn(fn -> signal_receiver_loop(parent) end)

      signal = Jido.Signal.new("test.signal", %{})
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

      signal = Jido.Signal.new("test.signal", %{})

      result = SensorDispatchBridge.forward_many([signal], dead_pid)

      assert result.forwarded == 0
      assert length(result.errors) == 1
      assert hd(result.errors).reason == :runtime_unavailable
    end

    test "returns empty result for empty list" do
      pid = spawn(fn -> receive_loop() end)

      result = SensorDispatchBridge.forward_many([], pid)

      assert result.forwarded == 0
      assert result.errors == []
    end
  end

  describe "forward_or_ignore/2" do
    test "returns :ok on successful forward" do
      parent = self()
      pid = spawn(fn -> signal_receiver_loop(parent) end)

      signal = Jido.Signal.new("test.signal", %{})

      assert :ok = SensorDispatchBridge.forward_or_ignore(signal, pid)
    end

    test "returns :ignored for invalid signal message" do
      pid = spawn(fn -> receive_loop() end)

      assert :ignored = SensorDispatchBridge.forward_or_ignore({:invalid, nil}, pid)
    end

    test "returns error for unavailable runtime" do
      dead_pid = spawn(fn -> nil end)
      Process.sleep(10)

      signal = Jido.Signal.new("test.signal", %{})

      assert {:error, :runtime_unavailable} =
               SensorDispatchBridge.forward_or_ignore(signal, dead_pid)
    end
  end

  # Helper functions for test processes

  defp receive_loop do
    receive do
      _ -> receive_loop()
    end
  end

  defp signal_receiver_loop(parent) do
    receive do
      {:signal, signal} ->
        send(parent, {:signal_received, signal})
        signal_receiver_loop(parent)

      _ ->
        signal_receiver_loop(parent)
    end
  end
end
