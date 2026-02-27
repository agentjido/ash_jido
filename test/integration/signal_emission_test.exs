defmodule AshJido.SignalEmissionTest do
  use ExUnit.Case, async: false

  defmodule ResourceWithSignals do
    use Ash.Resource,
      domain: AshJido.SignalEmissionTest.Domain,
      extensions: [AshJido],
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
    end

    actions do
      defaults([:read, :destroy])

      create :create do
        accept([:title])
      end

      update :update do
        accept([:title])
      end
    end

    jido do
      action(:create, emit_signals?: true, signal_dispatch: {:noop, []})
      action(:update, emit_signals?: true, signal_dispatch: {:noop, []})
      action(:destroy, emit_signals?: true, signal_dispatch: {:noop, []})
    end
  end

  defmodule ResourceMissingDispatch do
    use Ash.Resource,
      domain: AshJido.SignalEmissionTest.Domain,
      extensions: [AshJido],
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
    end

    actions do
      create :create do
        accept([:title])
      end
    end

    jido do
      action(:create, emit_signals?: true)
    end
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource(ResourceWithSignals)
      resource(ResourceMissingDispatch)
    end
  end

  defmodule CaptureSensor do
    use Jido.Sensor,
      name: "capture_sensor",
      schema: Zoi.object(%{})

    @impl true
    def init(_config, context) do
      {:ok, %{test_pid: context[:test_pid]}}
    end

    @impl true
    def handle_event(event, state) do
      send(state.test_pid, {:sensor_event, event})
      {:ok, state, []}
    end
  end

  describe "notification signals" do
    test "context signal dispatch overrides action DSL dispatch config" do
      context = %{domain: Domain, signal_dispatch: {:pid, target: self()}}

      {:ok, _resource} = ResourceWithSignals.Jido.Create.run(%{title: "Create Signal"}, context)

      assert_receive {:signal, %Jido.Signal{} = signal}
      assert signal.data.action == :create
      assert signal.data.resource == ResourceWithSignals
    end

    test "update actions emit notification signals" do
      {:ok, created} = ResourceWithSignals.Jido.Create.run(%{title: "Before"}, %{domain: Domain})
      context = %{domain: Domain, signal_dispatch: {:pid, target: self()}}

      {:ok, updated} =
        ResourceWithSignals.Jido.Update.run(%{id: created[:id], title: "After"}, context)

      assert updated[:title] == "After"
      assert_receive {:signal, %Jido.Signal{} = signal}
      assert signal.data.action == :update
      assert signal.data.resource == ResourceWithSignals
    end

    test "destroy actions emit notification signals" do
      {:ok, created} =
        ResourceWithSignals.Jido.Create.run(%{title: "To Delete"}, %{domain: Domain})

      context = %{domain: Domain, signal_dispatch: {:pid, target: self()}}

      assert {:ok, %{deleted: true}} =
               ResourceWithSignals.Jido.Destroy.run(%{id: created[:id]}, context)

      assert_receive {:signal, %Jido.Signal{} = signal}
      assert signal.data.action == :destroy
      assert signal.data.resource == ResourceWithSignals
    end

    test "returns validation error when emit_signals? is enabled and dispatch config is missing" do
      result =
        ResourceMissingDispatch.Jido.Create.run(%{title: "Missing dispatch"}, %{domain: Domain})

      assert {:error, %Jido.Action.Error.InvalidInputError{} = error} = result
      assert String.contains?(error.message, "signal dispatch configuration is required")
    end
  end

  describe "sensor bridge" do
    test "forwards signal dispatch messages to a sensor runtime" do
      {:ok, sensor_runtime} =
        Jido.Sensor.Runtime.start_link(
          sensor: CaptureSensor,
          config: %{},
          context: %{test_pid: self()}
        )

      signal =
        Jido.Signal.new!("ash_jido.sensor.forwarded", %{ok: true}, source: "/ash_jido/tests")

      assert :ok = AshJido.SensorDispatchBridge.forward({:signal, signal}, sensor_runtime)
      assert_receive {:sensor_event, ^signal}
    end

    test "returns an error for non-signal dispatch messages" do
      assert {:error, :invalid_signal_message} =
               AshJido.SensorDispatchBridge.forward(:invalid_message, self())
    end
  end
end
