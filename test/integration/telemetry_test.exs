defmodule AshJido.TelemetryTest do
  use ExUnit.Case, async: false

  @telemetry_events [
    [:jido, :action, :ash_jido, :start],
    [:jido, :action, :ash_jido, :stop],
    [:jido, :action, :ash_jido, :exception]
  ]

  defmodule ResourceWithTelemetry do
    use Ash.Resource,
      domain: AshJido.TelemetryTest.Domain,
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
      defaults([:read])

      create :create do
        accept([:title])
      end

      action :explode do
        run(fn _input, _context ->
          raise "telemetry boom"
        end)
      end
    end

    jido do
      action(:create, telemetry?: true, emit_signals?: true)
      action(:read, telemetry?: true)
      action(:explode, telemetry?: true)
    end
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource(ResourceWithTelemetry)
    end
  end

  describe "telemetry emission" do
    test "emits start and stop events for successful executions" do
      flush_telemetry_messages()
      handler_id = attach_telemetry_handler(self())
      on_exit(fn -> :telemetry.detach(handler_id) end)

      ResourceWithTelemetry
      |> Ash.Changeset.for_create(:create, %{title: "hello"}, domain: Domain)
      |> Ash.create!(domain: Domain)

      assert {:ok, results} = ResourceWithTelemetry.Jido.Read.run(%{}, %{domain: Domain})
      assert is_list(results)

      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :start], start, start_meta}
      assert start.system_time > 0
      assert start_meta.resource == ResourceWithTelemetry
      assert start_meta.ash_action_name == :read
      assert start_meta.ash_action_type == :read
      assert start_meta.generated_module == ResourceWithTelemetry.Jido.Read
      assert start_meta.domain == Domain
      assert start_meta.tenant == nil
      assert start_meta.actor_present? == false
      assert start_meta.signaling_enabled? == false
      assert start_meta.read_load_configured? == false

      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :stop], stop, stop_meta}
      assert stop.system_time > 0
      assert stop.duration > 0
      assert stop_meta.result_status == :ok
      assert stop_meta.signal_sent_count == 0
      assert stop_meta.signal_failed_count == 0
      refute Map.has_key?(stop_meta, :signal_failures)

      refute_receive {:telemetry_event, [:jido, :action, :ash_jido, :exception], _, _}
    end

    test "emits start and stop with :error status for mapped validation errors" do
      flush_telemetry_messages()
      handler_id = attach_telemetry_handler(self())
      on_exit(fn -> :telemetry.detach(handler_id) end)

      result =
        ResourceWithTelemetry.Jido.Create.run(%{title: "missing dispatch"}, %{domain: Domain})

      assert {:error, %Jido.Action.Error.InvalidInputError{} = error} = result
      assert String.contains?(error.message, "signal dispatch configuration is required")

      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :start], _start, start_meta}
      assert start_meta.generated_module == ResourceWithTelemetry.Jido.Create
      assert start_meta.ash_action_name == :create
      assert start_meta.ash_action_type == :create
      assert start_meta.signaling_enabled? == true

      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :stop], _stop, stop_meta}
      assert stop_meta.result_status == :error
      assert stop_meta.signal_sent_count == 0
      assert stop_meta.signal_failed_count == 0

      refute_receive {:telemetry_event, [:jido, :action, :ash_jido, :exception], _, _}
    end

    test "emits start and exception events for raised runtime exceptions" do
      flush_telemetry_messages()
      handler_id = attach_telemetry_handler(self())
      on_exit(fn -> :telemetry.detach(handler_id) end)

      result = ResourceWithTelemetry.Jido.Explode.run(%{}, %{domain: Domain})

      assert {:error, %Jido.Action.Error.ExecutionFailureError{}} = result

      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :start], _start, start_meta}
      assert start_meta.generated_module == ResourceWithTelemetry.Jido.Explode
      assert start_meta.ash_action_name == :explode
      assert start_meta.ash_action_type == :action

      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :exception], exception,
                      metadata}

      assert exception.system_time > 0
      assert exception.duration > 0
      assert metadata.result_status == :error
      assert metadata.error_kind == :error
      assert String.contains?(metadata.error_reason, "telemetry boom")
      assert is_binary(metadata.error_stacktrace)

      refute_receive {:telemetry_event, [:jido, :action, :ash_jido, :stop], _, _}
    end
  end

  defp attach_telemetry_handler(test_pid) do
    handler_id = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach_many(
        handler_id,
        @telemetry_events,
        fn event, measurements, metadata, pid ->
          send(pid, {:telemetry_event, event, measurements, metadata})
        end,
        test_pid
      )

    handler_id
  end

  defp flush_telemetry_messages do
    receive do
      {:telemetry_event, _event, _measurements, _metadata} ->
        flush_telemetry_messages()
    after
      0 ->
        :ok
    end
  end
end
