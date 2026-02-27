defmodule AshJido.GuideExamplesTest do
  use ExUnit.Case, async: false

  @telemetry_events [
    [:jido, :action, :ash_jido, :start],
    [:jido, :action, :ash_jido, :stop],
    [:jido, :action, :ash_jido, :exception]
  ]

  defmodule Author do
    use Ash.Resource,
      domain: AshJido.GuideExamplesTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
    end

    actions do
      defaults([:read, :destroy])

      create :create do
        accept([:name])
      end
    end
  end

  defmodule Post do
    use Ash.Resource,
      domain: AshJido.GuideExamplesTest.Domain,
      extensions: [AshJido],
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:status, :atom, default: :draft, public?: true)
    end

    relationships do
      belongs_to(:author, Author, allow_nil?: false, public?: true)
    end

    actions do
      defaults([:read, :destroy])

      create :create do
        argument(:title, :string, allow_nil?: false)
        argument(:author_id, :uuid, allow_nil?: false)

        change(set_attribute(:title, arg(:title)))
        change(set_attribute(:author_id, arg(:author_id)))
      end

      update :publish do
        accept([])
        change(set_attribute(:status, :published))
      end
    end

    jido do
      action(:create,
        name: "create_post",
        category: "ash.create",
        tags: ["guide", "content"],
        vsn: "1.0.0",
        emit_signals?: true,
        signal_dispatch: {:noop, []},
        telemetry?: true
      )

      action(:read, name: "list_posts", load: [:author], telemetry?: true)

      action(:publish,
        name: "publish_post",
        emit_signals?: true,
        signal_dispatch: {:noop, []},
        signal_type: "docs.post.published",
        signal_source: "/docs/posts",
        telemetry?: true
      )
    end
  end

  defmodule ProtectedDocument do
    use Ash.Resource,
      domain: AshJido.GuideExamplesTest.Domain,
      extensions: [AshJido],
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

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

    policies do
      policy action_type(:create) do
        authorize_if(actor_present())
      end
    end

    jido do
      action(:create, name: "create_protected_doc")
    end
  end

  defmodule ContextEcho do
    use Ash.Resource,
      domain: AshJido.GuideExamplesTest.Domain,
      extensions: [AshJido],
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
    end

    actions do
      action :inspect_context, :map do
        run(fn _input, context ->
          actor = context.actor

          {:ok,
           %{
             actor_id: actor && Map.get(actor, :id),
             actor_present?: not is_nil(actor),
             authorize?: context.authorize?,
             tenant: context.tenant
           }}
        end)
      end
    end

    jido do
      action(:inspect_context, name: "inspect_context")
    end
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource(Author)
      resource(Post)
      resource(ProtectedDocument)
      resource(ContextEcho)
    end
  end

  defmodule CaptureSensor do
    use Jido.Sensor,
      name: "guide_capture_sensor",
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

  describe "resource-to-action walkthrough" do
    test "create/read/update flow works with static read load" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{name: "Ada"}, domain: Domain)
        |> Ash.create!(domain: Domain)

      {:ok, post} =
        Post.Jido.Create.run(
          %{title: "Ash + Jido", author_id: author.id},
          %{domain: Domain}
        )

      {:ok, posts} = Post.Jido.Read.run(%{}, %{domain: Domain})
      loaded_post = Enum.find(posts, &(&1[:id] == post[:id]))

      assert loaded_post[:author][:id] == author.id
      assert loaded_post[:author][:name] == "Ada"

      {:ok, published} = Post.Jido.Publish.run(%{id: post[:id]}, %{domain: Domain})
      assert published[:status] == :published
    end
  end

  describe "context walkthrough" do
    test "scope actor is honored when actor key is omitted" do
      actor = %{id: "scope_actor", name: "Scope User"}

      assert {:ok, doc} =
               ProtectedDocument.Jido.Create.run(
                 %{title: "Scoped Secret"},
                 %{domain: Domain, scope: %{actor: actor}}
               )

      assert doc[:title] == "Scoped Secret"
    end

    test "explicit actor nil overrides actor from scope" do
      actor = %{id: "scope_actor_nil", name: "Scope Nil User"}

      assert {:error, error} =
               ProtectedDocument.Jido.Create.run(
                 %{title: "Scoped Secret"},
                 %{domain: Domain, scope: %{actor: actor}, actor: nil}
               )

      assert error.details.reason == :forbidden
    end

    test "authorize? false can bypass actor policy checks for protected create" do
      assert {:ok, doc} =
               ProtectedDocument.Jido.Create.run(
                 %{title: "Policy Bypass"},
                 %{domain: Domain, actor: nil, authorize?: false}
               )

      assert doc[:title] == "Policy Bypass"
    end

    test "tenant and scope actor are visible in runtime action context" do
      actor = %{id: "tenant_scope_actor"}

      assert {:ok, context_info} =
               ContextEcho.Jido.InspectContext.run(
                 %{},
                 %{domain: Domain, tenant: "tenant_a", scope: %{actor: actor}}
               )

      assert context_info[:tenant] == "tenant_a"
      assert context_info[:actor_id] == "tenant_scope_actor"
      assert context_info[:actor_present?] == true
      assert is_boolean(context_info[:authorize?])
    end
  end

  describe "tools walkthrough" do
    test "exports action metadata and callable tool maps" do
      actions = AshJido.Tools.actions(Post)
      assert Post.Jido.Create in actions

      assert Post.Jido.Create.tags() == ["guide", "content"]
      assert Post.Jido.Create.category() == "ash.create"
      assert Post.Jido.Create.vsn() == "1.0.0"

      user_tools = AshJido.Tools.tools(AshJido.Test.User)
      create_user_tool = Enum.find(user_tools, &(&1.name == "create_user"))

      assert create_user_tool != nil
      assert is_function(create_user_tool.function, 2)

      assert {:ok, json} =
               create_user_tool.function.(
                 %{"name" => "Tool User", "email" => "tool-user@example.com"},
                 %{domain: AshJido.Test.Domain}
               )

      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["name"] == "Tool User"
      assert decoded["email"] == "tool-user@example.com"
    end
  end

  describe "signals, telemetry, and sensors walkthrough" do
    test "supports signal dispatch override, telemetry events, and sensor bridge forwarding" do
      flush_telemetry_messages()
      handler_id = attach_telemetry_handler(self())
      on_exit(fn -> :telemetry.detach(handler_id) end)

      author =
        Author
        |> Ash.Changeset.for_create(:create, %{name: "Signal Author"}, domain: Domain)
        |> Ash.create!(domain: Domain)

      assert {:ok, _post} =
               Post.Jido.Create.run(
                 %{title: "Signal Post", author_id: author.id},
                 %{domain: Domain, signal_dispatch: {:pid, target: self()}}
               )

      assert_receive {:signal, %Jido.Signal{} = signal}
      assert signal.data.action == :create

      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :start], start, start_meta}
      assert start.system_time > 0
      assert start_meta.resource == Post
      assert start_meta.ash_action_name == :create

      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :stop], stop, stop_meta}
      assert stop.duration > 0
      assert stop_meta.result_status == :ok

      {:ok, sensor_runtime} =
        Jido.Sensor.Runtime.start_link(
          sensor: CaptureSensor,
          config: %{},
          context: %{test_pid: self()}
        )

      assert :ok = AshJido.SensorDispatchBridge.forward({:signal, signal}, sensor_runtime)
      assert_receive {:sensor_event, ^signal}

      batch =
        AshJido.SensorDispatchBridge.forward_many(
          [{:signal, signal}, :not_a_signal],
          sensor_runtime
        )

      assert batch.forwarded == 1
      assert batch.errors == [%{message: :not_a_signal, reason: :invalid_signal_message}]

      assert :ignored =
               AshJido.SensorDispatchBridge.forward_or_ignore(:not_a_signal, sensor_runtime)
    end
  end

  describe "failure semantics walkthrough" do
    test "missing domain raises argument error" do
      assert_raise ArgumentError, ~r/AshJido: :domain must be provided in context/, fn ->
        Post.Jido.Read.run(%{}, %{})
      end
    end

    test "missing id for update action returns a deterministic error" do
      assert {:error, %Jido.Action.Error.ExecutionFailureError{} = error} =
               Post.Jido.Publish.run(%{}, %{domain: Domain})

      assert error.message == "Update actions require an 'id' parameter"
    end

    test "missing dispatch config returns invalid input when signaling is enabled" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{name: "Missing Dispatch Author"}, domain: Domain)
        |> Ash.create!(domain: Domain)

      assert {:error, %Jido.Action.Error.InvalidInputError{} = error} =
               Post.Jido.Create.run(
                 %{title: "Missing Dispatch", author_id: author.id},
                 %{domain: Domain, signal_dispatch: nil}
               )

      assert String.contains?(error.message, "signal dispatch configuration is required")
    end

    test "dispatch failures preserve action success and increment telemetry failure counters" do
      flush_telemetry_messages()
      handler_id = attach_telemetry_handler(self())
      on_exit(fn -> :telemetry.detach(handler_id) end)

      author =
        Author
        |> Ash.Changeset.for_create(:create, %{name: "Dispatch Failure Author"}, domain: Domain)
        |> Ash.create!(domain: Domain)

      missing_named_dispatch =
        {:named, [target: {:name, :ash_jido_missing_target}, delivery_mode: :sync]}

      assert {:ok, created} =
               Post.Jido.Create.run(
                 %{title: "Dispatch Failure Post", author_id: author.id},
                 %{domain: Domain, signal_dispatch: missing_named_dispatch}
               )

      assert created[:title] == "Dispatch Failure Post"

      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :start], _start, _start_meta}
      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :stop], _stop, stop_meta}
      assert stop_meta.result_status == :ok
      assert stop_meta.signal_failed_count >= 1
      assert is_list(stop_meta.signal_failures)
      assert length(stop_meta.signal_failures) >= 1
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
