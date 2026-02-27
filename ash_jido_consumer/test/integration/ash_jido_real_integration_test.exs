defmodule AshJidoConsumer.RealIntegrationTest do
  use AshJidoConsumer.DataCase, async: false

  alias AshJidoConsumer.Accounts
  alias AshJidoConsumer.Accounts.User
  alias AshJidoConsumer.Content
  alias AshJidoConsumer.Content.Author
  alias AshJidoConsumer.Content.Post
  alias AshJidoConsumer.Tenanting
  alias AshJidoConsumer.Tenanting.Note

  @telemetry_events [
    [:jido, :action, :ash_jido, :start],
    [:jido, :action, :ash_jido, :stop],
    [:jido, :action, :ash_jido, :exception]
  ]

  defmodule TraceCollector do
    use Ash.Tracer

    @pid_key {__MODULE__, :test_pid}

    def start_span(type, name), do: notify({:ash_trace_start, type, name})
    def stop_span, do: notify(:ash_trace_stop)
    def get_span_context, do: :none
    def set_span_context(_context), do: :ok
    def set_error(_error), do: :ok
    def set_error(_error, _opts), do: :ok
    def trace_type?(_type), do: true
    def set_handled_error(_error, _opts), do: :ok
    def set_metadata(type, metadata), do: notify({:ash_trace_metadata, type, metadata})

    def set_test_pid(pid), do: :persistent_term.put(@pid_key, pid)

    def clear_test_pid do
      case :persistent_term.get(@pid_key, :undefined) do
        :undefined -> :ok
        _ -> :persistent_term.erase(@pid_key)
      end
    end

    defp notify(message) do
      case :persistent_term.get(@pid_key, :undefined) do
        :undefined -> :ok
        pid -> send(pid, message)
      end

      :ok
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

  setup do
    on_exit(fn -> TraceCollector.clear_test_pid() end)
    :ok
  end

  describe "context passthrough" do
    test "authorize? can disable authorization when needed" do
      params = %{name: "No Actor", email: "no-actor@example.com"}

      result = User.Jido.Create.run(params, %{domain: Accounts, actor: nil})
      assert {:error, error} = result
      assert error.details.reason == :forbidden

      bypassed_result =
        User.Jido.Create.run(params, %{domain: Accounts, actor: nil, authorize?: false})

      assert {:ok, created} = bypassed_result
      assert created[:name] == "No Actor"
      assert created[:email] == "no-actor@example.com"
    end

    test "scope can provide actor context for policy-aware actions" do
      params = %{name: "Scope User", email: "scope-user@example.com"}
      actor = %{id: "scope_actor_1"}
      scope = %{actor: actor}

      assert {:ok, created} = User.Jido.Create.run(params, %{domain: Accounts, scope: scope})
      assert created[:name] == "Scope User"
    end

    test "explicit actor nil overrides actor provided by scope" do
      params = %{name: "Scope Nil", email: "scope-nil@example.com"}
      scope = %{actor: %{id: "scope_actor_2"}}

      result = User.Jido.Create.run(params, %{domain: Accounts, scope: scope, actor: nil})

      assert {:error, error} = result
      assert error.details.reason == :forbidden
    end

    test "context and tracer are visible in runtime action context" do
      TraceCollector.set_test_pid(self())
      flush_trace_messages()

      runtime_context = %{
        domain: Accounts,
        context: %{shared: %{trace_id: "trace-123"}},
        tracer: [TraceCollector],
        tenant: "tenant-a"
      }

      assert {:ok, _} = User.Jido.InspectRuntime.run(%{}, runtime_context)
      assert_receive {:runtime_context, runtime_info}
      assert runtime_info[:trace_id] == "trace-123"
      assert runtime_info[:tracer_present?] == true
      assert runtime_info[:tenant] == "tenant-a"
      assert runtime_info[:actor_present?] == false
      assert is_boolean(runtime_info[:authorize?])

      assert_receive {:ash_trace_start, _type, _name}
      assert_receive {:ash_trace_metadata, _type, metadata}
      assert metadata.tenant == "tenant-a"
    end

    test "timeout is enforced for slow runtime actions" do
      result = User.Jido.SlowRuntime.run(%{}, %{domain: Accounts, timeout: 1})

      assert {:error, error} = result
      assert Regex.match?(~r/timeout|timed out/i, error.message)
    end
  end

  describe "relationship-aware reads" do
    test "read actions return loaded relationship data" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{name: "Ada"}, domain: Content)
        |> Ash.create!(domain: Content)

      {:ok, _post} =
        Post.Jido.Create.run(
          %{title: "Loaded Post", author_id: author.id},
          %{domain: Content, signal_dispatch: {:noop, []}}
        )

      assert {:ok, posts} = Post.Jido.Read.run(%{}, %{domain: Content})
      loaded_post = Enum.find(posts, &(&1[:title] == "Loaded Post"))

      assert loaded_post[:author][:id] == author.id
      assert loaded_post[:author][:name] == "Ada"
    end
  end

  describe "action metadata and tools" do
    test "generated action metadata includes category tags and version" do
      assert User.Jido.Create.category() == "ash.consumer.accounts"
      assert User.Jido.Create.tags() == ["accounts", "write"]
      assert User.Jido.Create.vsn() == "1.0.0"
    end

    test "AshJido.Tools exports callable tool definitions for generated actions" do
      assert User.Jido.Create in AshJido.Tools.actions(User)
      assert User.Jido.Create in AshJido.Tools.actions(Accounts)

      create_tool =
        Accounts
        |> AshJido.Tools.tools()
        |> Enum.find(&(&1.name == "create_user"))

      assert create_tool != nil
      assert is_function(create_tool.function, 2)
      assert is_map(create_tool.parameters_schema)

      unique_email = "tool-#{System.unique_integer([:positive])}@example.com"

      assert {:ok, json} =
               create_tool.function.(
                 %{"name" => "Tool User", "email" => unique_email},
                 %{domain: Accounts, actor: %{id: "tool_actor"}}
               )

      payload = Jason.decode!(json)
      assert payload["name"] == "Tool User"
      assert payload["email"] == unique_email
    end
  end

  describe "notification signals" do
    test "create, update, and destroy emit signals to pid dispatch targets" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{name: "Signal Author"}, domain: Content)
        |> Ash.create!(domain: Content)

      dispatch_context = %{domain: Content, signal_dispatch: {:pid, target: self()}}

      assert {:ok, created} =
               Post.Jido.Create.run(
                 %{title: "Signal Post", author_id: author.id},
                 dispatch_context
               )

      assert_receive {:signal, %Jido.Signal{} = create_signal}
      assert create_signal.data.action == :create
      assert create_signal.data.resource == Post
      assert create_signal.type == "ash_jido_consumer.content.post.created"
      assert create_signal.source == "/ash_jido_consumer/content/post"

      assert {:ok, updated} =
               Post.Jido.Update.run(
                 %{id: created[:id], title: "Signal Post Updated"},
                 dispatch_context
               )

      assert updated[:title] == "Signal Post Updated"
      assert_receive {:signal, %Jido.Signal{} = update_signal}
      assert update_signal.data.action == :update
      assert update_signal.data.resource == Post

      assert {:ok, %{deleted: true}} =
               Post.Jido.Destroy.run(%{id: created[:id]}, dispatch_context)

      assert_receive {:signal, %Jido.Signal{} = destroy_signal}
      assert destroy_signal.data.action == :destroy
      assert destroy_signal.data.resource == Post
    end

    test "missing dispatch config returns a validation error before execution" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{name: "Missing Dispatch"}, domain: Content)
        |> Ash.create!(domain: Content)

      result = Post.Jido.Create.run(%{title: "Missing", author_id: author.id}, %{domain: Content})

      assert {:error, %Jido.Action.Error.InvalidInputError{} = error} = result
      assert String.contains?(error.message, "signal dispatch configuration is required")
    end

    test "dispatch failures do not fail the action and are reflected in telemetry metadata" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{name: "Dispatch Failure"}, domain: Content)
        |> Ash.create!(domain: Content)

      flush_telemetry_messages()
      handler_id = attach_telemetry_handler(self())
      on_exit(fn -> :telemetry.detach(handler_id) end)

      missing_named_dispatch =
        {:named, [target: {:name, :ash_jido_missing_target}, delivery_mode: :sync]}

      assert {:ok, created} =
               Post.Jido.Create.run(
                 %{title: "Telemetry Failure", author_id: author.id},
                 %{domain: Content, signal_dispatch: missing_named_dispatch}
               )

      assert created[:title] == "Telemetry Failure"

      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :start], _start, _start_meta}
      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :stop], _stop, stop_meta}

      assert stop_meta.result_status == :ok
      assert stop_meta.signal_sent_count == 0
      assert stop_meta.signal_failed_count >= 1
      assert is_list(stop_meta.signal_failures)
      assert length(stop_meta.signal_failures) >= 1
    end

    test "mixed dispatch keeps action success while reporting telemetry failures" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{name: "Mixed Dispatch"}, domain: Content)
        |> Ash.create!(domain: Content)

      flush_telemetry_messages()
      flush_signal_messages()

      handler_id = attach_telemetry_handler(self())
      on_exit(fn -> :telemetry.detach(handler_id) end)

      mixed_dispatch = [
        {:pid, [target: self()]},
        {:named, [target: {:name, :ash_jido_missing_target}, delivery_mode: :sync]}
      ]

      assert {:ok, created} =
               Post.Jido.Create.run(
                 %{title: "Mixed Dispatch Post", author_id: author.id},
                 %{domain: Content, signal_dispatch: mixed_dispatch}
               )

      assert created[:title] == "Mixed Dispatch Post"
      assert_receive {:signal, %Jido.Signal{} = signal}
      assert signal.type == "ash_jido_consumer.content.post.created"
      assert signal.source == "/ash_jido_consumer/content/post"

      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :start], _start, _start_meta}
      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :stop], _stop, stop_meta}

      assert stop_meta.result_status == :ok
      assert stop_meta.signal_failed_count >= 1
      assert is_list(stop_meta.signal_failures)
    end
  end

  describe "telemetry" do
    test "start and stop events include stable metadata for success paths" do
      flush_telemetry_messages()
      handler_id = attach_telemetry_handler(self())
      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert {:ok, _users} = User.Jido.Read.run(%{}, %{domain: Accounts})

      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :start], _start, start_meta}
      assert start_meta.resource == User
      assert start_meta.generated_module == User.Jido.Read
      assert start_meta.ash_action_name == :read
      assert start_meta.ash_action_type == :read
      assert start_meta.domain == Accounts
      assert start_meta.signaling_enabled? == false

      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :stop], stop, stop_meta}
      assert stop.duration > 0
      assert stop_meta.result_status == :ok
      assert stop_meta.signal_sent_count == 0
      assert stop_meta.signal_failed_count == 0

      refute_receive {:telemetry_event, [:jido, :action, :ash_jido, :exception], _, _}
    end

    test "exception events are emitted for raised runtime exceptions" do
      flush_telemetry_messages()
      handler_id = attach_telemetry_handler(self())
      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert {:error, %Jido.Action.Error.InternalError{} = error} =
               User.Jido.Explode.run(%{}, %{domain: Accounts})

      assert String.contains?(error.message, "user action boom")

      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :start], _start, _start_meta}

      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :exception], exception,
                      exception_meta}

      assert exception.duration > 0
      assert exception_meta.result_status == :error
      assert exception_meta.error_kind == :error
      assert String.contains?(exception_meta.error_reason, "user action boom")
      assert is_binary(exception_meta.error_stacktrace)

      refute_receive {:telemetry_event, [:jido, :action, :ash_jido, :stop], _, _}
    end
  end

  describe "database constraint mapping" do
    test "unique identity violations are returned as action errors" do
      params = %{name: "Uniq User", email: "unique@example.com"}
      actor_context = %{domain: Accounts, actor: %{id: "actor_1"}}

      assert {:ok, _created} = User.Jido.Create.run(params, actor_context)

      assert {:error, %Jido.Action.Error.InvalidInputError{} = error} =
               User.Jido.Create.run(params, actor_context)

      assert String.contains?(String.downcase(error.message), "email")
    end

    test "foreign key violations are returned as action errors" do
      result =
        Post.Jido.Create.run(
          %{title: "Bad FK", author_id: Ecto.UUID.generate()},
          %{domain: Content, signal_dispatch: {:noop, []}}
        )

      assert {:error, %Jido.Action.Error.InvalidInputError{} = error} = result
      assert String.contains?(String.downcase(error.message), "author")
    end
  end

  describe "failure semantics" do
    test "missing domain raises an argument error for generated actions" do
      assert_raise ArgumentError, ~r/AshJido: :domain must be provided in context/, fn ->
        User.Jido.Read.run(%{}, %{})
      end
    end

    test "update actions require id and return deterministic errors when missing" do
      assert {:error, %Jido.Action.Error.ExecutionFailureError{} = error} =
               Post.Jido.Update.run(
                 %{title: "Missing ID"},
                 %{domain: Content, signal_dispatch: {:noop, []}}
               )

      assert error.message == "Update actions require an 'id' parameter"
    end
  end

  describe "sensor bridge" do
    test "dispatched signals can be forwarded to a sensor runtime using supported envelopes" do
      {:ok, sensor_runtime} =
        Jido.Sensor.Runtime.start_link(
          sensor: CaptureSensor,
          config: %{},
          context: %{test_pid: self()}
        )

      signal =
        Jido.Signal.new!("ash_jido.consumer.sensor_bridge", %{ok: true},
          source: "/ash_jido/consumer"
        )

      assert :ok = AshJido.SensorDispatchBridge.forward(signal, sensor_runtime)
      assert :ok = AshJido.SensorDispatchBridge.forward({:signal, signal}, sensor_runtime)
      assert :ok = AshJido.SensorDispatchBridge.forward({:signal, {:ok, signal}}, sensor_runtime)

      assert_receive {:sensor_event, ^signal}
      assert_receive {:sensor_event, ^signal}
      assert_receive {:sensor_event, ^signal}
    end

    test "forward_many and forward_or_ignore keep mailbox integrations safe" do
      {:ok, sensor_runtime} =
        Jido.Sensor.Runtime.start_link(
          sensor: CaptureSensor,
          config: %{},
          context: %{test_pid: self()}
        )

      signal =
        Jido.Signal.new!("ash_jido.consumer.sensor_bridge.batch", %{ok: true},
          source: "/ash_jido/consumer"
        )

      result =
        AshJido.SensorDispatchBridge.forward_many(
          [signal, {:signal, signal}, :invalid_message],
          sensor_runtime
        )

      assert result.forwarded == 2
      assert result.errors == [%{message: :invalid_message, reason: :invalid_signal_message}]

      assert :ignored =
               AshJido.SensorDispatchBridge.forward_or_ignore(:invalid_message, sensor_runtime)

      assert_receive {:sensor_event, ^signal}
      assert_receive {:sensor_event, ^signal}
    end

    test "runtime availability errors are deterministic for unavailable targets" do
      signal =
        Jido.Signal.new!("ash_jido.consumer.sensor_bridge.unavailable", %{ok: false},
          source: "/ash_jido/consumer"
        )

      assert {:error, :runtime_unavailable} =
               AshJido.SensorDispatchBridge.forward(signal, :ash_jido_consumer_missing_runtime)
    end
  end

  describe "multitenancy" do
    test "attribute multitenancy scopes create and read operations by tenant" do
      assert {:ok, note_a} =
               Note.Jido.Create.run(
                 %{body: "Tenant A note"},
                 %{domain: Tenanting, tenant: "tenant_a"}
               )

      assert {:ok, note_b} =
               Note.Jido.Create.run(
                 %{body: "Tenant B note"},
                 %{domain: Tenanting, tenant: "tenant_b"}
               )

      assert note_a[:tenant_id] == "tenant_a"
      assert note_b[:tenant_id] == "tenant_b"

      assert {:ok, tenant_a_notes} =
               Note.Jido.Read.run(%{}, %{domain: Tenanting, tenant: "tenant_a"})

      assert {:ok, tenant_b_notes} =
               Note.Jido.Read.run(%{}, %{domain: Tenanting, tenant: "tenant_b"})

      assert Enum.count(tenant_a_notes) == 1
      assert Enum.count(tenant_b_notes) == 1
      assert Enum.at(tenant_a_notes, 0)[:body] == "Tenant A note"
      assert Enum.at(tenant_b_notes, 0)[:body] == "Tenant B note"
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

  defp flush_signal_messages do
    receive do
      {:signal, _signal} ->
        flush_signal_messages()
    after
      0 ->
        :ok
    end
  end

  defp flush_trace_messages do
    receive do
      {:ash_trace_start, _type, _name} ->
        flush_trace_messages()

      {:ash_trace_metadata, _type, _metadata} ->
        flush_trace_messages()

      :ash_trace_stop ->
        flush_trace_messages()
    after
      0 ->
        :ok
    end
  end
end
