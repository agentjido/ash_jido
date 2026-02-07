defmodule AshJido.NotifierTest do
  use ExUnit.Case, async: false

  alias Ash.Notifier.Notification
  alias AshJido.Notifier

  @moduletag :capture_log

  test "returns :ok when no publications are configured" do
    notification =
      build_notification(
        AshJido.Test.User,
        :register,
        struct(AshJido.Test.User, %{id: "123", name: "Jane", email: "jane@example.com"})
      )

    assert :ok = Notifier.notify(notification)
  end

  test "logs warning and returns :ok when no signal bus is configured" do
    previous = Application.get_env(:ash_jido, :signal_bus)
    Application.delete_env(:ash_jido, :signal_bus)
    on_exit(fn -> Application.put_env(:ash_jido, :signal_bus, previous) end)

    notification =
      build_notification(
        AshJido.Test.NoBusResource,
        :create,
        struct(AshJido.Test.NoBusResource, %{id: "123", name: "No Bus"})
      )

    assert :ok = Notifier.notify(notification)
  end

  test "skips conditional publications when condition returns false" do
    start_supervised!({Jido.Signal.Bus, name: :ash_jido_test_bus})

    assert {:ok, _subscription_id} =
             Jido.Signal.Bus.subscribe(
               :ash_jido_test_bus,
               "**",
               dispatch: {:pid, target: self()}
             )

    previous = struct(AshJido.Test.ReactiveResource, %{id: "r-1", name: "Name", status: :draft})
    changeset = Ash.Changeset.for_update(previous, :update, %{name: "Updated Name"})

    notification =
      build_notification(
        AshJido.Test.ReactiveResource,
        :update,
        struct(AshJido.Test.ReactiveResource, %{id: "r-1", name: "Updated Name", status: :draft}),
        changeset: changeset
      )

    assert :ok = Notifier.notify(notification)
    assert_receive {:signal, %Jido.Signal{type: "test.reactive_resource.update"}}, 500
    refute_receive {:signal, %Jido.Signal{type: "test.resource.conditional"}}, 200
  end

  defp build_notification(resource, action_name, data, opts \\ []) do
    %Notification{
      resource: resource,
      action: Ash.Resource.Info.action(resource, action_name),
      data: data,
      changeset: Keyword.get(opts, :changeset),
      actor: Keyword.get(opts, :actor),
      metadata: %{}
    }
  end
end
