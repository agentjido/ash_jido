defmodule AshJidoConsumer.GuideWalkthroughTest do
  use AshJidoConsumer.DataCase, async: false

  alias AshJidoConsumer.Accounts
  alias AshJidoConsumer.Accounts.User
  alias AshJidoConsumer.Content
  alias AshJidoConsumer.Content.Author
  alias AshJidoConsumer.Content.Post

  @telemetry_events [
    [:jido, :action, :ash_jido, :start],
    [:jido, :action, :ash_jido, :stop],
    [:jido, :action, :ash_jido, :exception]
  ]

  describe "consumer walkthrough examples" do
    test "executes full CRUD flow against AshPostgres" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{name: "Guide Author"}, domain: Content)
        |> Ash.create!(domain: Content)

      context = %{domain: Content, signal_dispatch: {:noop, []}}

      assert {:ok, created} =
               Post.Jido.Create.run(
                 %{title: "Guide CRUD", author_id: author.id},
                 context
               )

      assert {:ok, updated} =
               Post.Jido.Update.run(
                 %{id: created[:id], title: "Guide CRUD Updated"},
                 context
               )

      assert updated[:title] == "Guide CRUD Updated"

      assert {:ok, %{deleted: true}} = Post.Jido.Destroy.run(%{id: created[:id]}, context)
    end

    test "scope actor can satisfy policy for protected account actions" do
      unique_email = "scope-#{System.unique_integer([:positive])}@example.com"

      assert {:ok, created} =
               User.Jido.Create.run(
                 %{name: "Scope Guide", email: unique_email},
                 %{domain: Accounts, scope: %{actor: %{id: "scope_actor_guide"}}}
               )

      assert created[:email] == unique_email
    end

    test "read actions include configured relationship load data" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{name: "Loaded Author"}, domain: Content)
        |> Ash.create!(domain: Content)

      assert {:ok, _created} =
               Post.Jido.Create.run(
                 %{title: "Loaded Guide Post", author_id: author.id},
                 %{domain: Content, signal_dispatch: {:noop, []}}
               )

      assert {:ok, posts} = Post.Jido.Read.run(%{}, %{domain: Content})
      loaded_post = Enum.find(posts, &(&1[:title] == "Loaded Guide Post"))

      assert loaded_post[:author][:id] == author.id
      assert loaded_post[:author][:name] == "Loaded Author"
    end

    test "signaling and telemetry can be observed for create actions" do
      flush_telemetry_messages()
      handler_id = attach_telemetry_handler(self())
      on_exit(fn -> :telemetry.detach(handler_id) end)

      author =
        Author
        |> Ash.Changeset.for_create(:create, %{name: "Signal Guide Author"}, domain: Content)
        |> Ash.create!(domain: Content)

      assert {:ok, _post} =
               Post.Jido.Create.run(
                 %{title: "Signal Guide Post", author_id: author.id},
                 %{domain: Content, signal_dispatch: {:pid, target: self()}}
               )

      assert_receive {:signal, %Jido.Signal{} = signal}
      assert signal.data.action == :create

      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :start], _start, _start_meta}
      assert_receive {:telemetry_event, [:jido, :action, :ash_jido, :stop], stop, stop_meta}
      assert stop.duration > 0
      assert stop_meta.result_status == :ok

      refute_receive {:telemetry_event, [:jido, :action, :ash_jido, :exception], _, _}
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
