defmodule AshJido.NotifierTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Ash.Notifier.Notification
  alias AshJido.Notifier
  alias AshJido.Test.{NoBusResource, ReactiveResource}

  def configured_bus, do: :ash_jido_notifier_bus
  def no_bus, do: nil
  def invalid_bus, do: raise("invalid bus")

  setup do
    previous = Application.get_env(:ash_jido, :signal_bus)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:ash_jido, :signal_bus)
      else
        Application.put_env(:ash_jido, :signal_bus, previous)
      end
    end)

    :ok
  end

  test "returns cleanly when no publication matches" do
    action = Ash.Resource.Info.action(AshJido.Test.User, :register)

    assert :ok =
             Notifier.notify(%Notification{
               resource: AshJido.Test.User,
               action: action,
               data: nil
             })

    refute Notifier.requires_original_data?(AshJido.Test.User, action)
  end

  test "uses the application bus and resolves an MFA" do
    start_supervised!({Jido.Signal.Bus, name: :ash_jido_notifier_bus})

    assert {:ok, _subscription} =
             Jido.Signal.Bus.subscribe(:ash_jido_notifier_bus, "**", target: self())

    Application.put_env(:ash_jido, :signal_bus, {__MODULE__, :configured_bus, []})

    notification = no_bus_notification()
    assert :ok = Notifier.notify(notification)
    assert_receive {:signal, %Jido.Signal{type: "test.no_bus.created"}}, 1_000
  end

  test "logs missing and invalid MFA bus values" do
    Application.delete_env(:ash_jido, :signal_bus)

    assert capture_log(fn -> assert :ok = Notifier.notify(no_bus_notification()) end) =~
             "has no signal bus configured"

    Application.put_env(:ash_jido, :signal_bus, {__MODULE__, :no_bus, []})

    assert capture_log(fn -> assert :ok = Notifier.notify(no_bus_notification()) end) =~
             "has no signal bus configured"

    Application.put_env(:ash_jido, :signal_bus, {__MODULE__, :invalid_bus, []})

    assert capture_log(fn -> assert :ok = Notifier.notify(no_bus_notification()) end) =~
             "failed resolving signal bus MFA"
  end

  test "filters false conditions and requests previous state only when configured" do
    action = Ash.Resource.Info.action(ReactiveResource, :update)
    data = %ReactiveResource{id: "id", name: "Name", status: :draft}

    assert capture_log(fn ->
             assert :ok =
                      Notifier.notify(%Notification{
                        resource: ReactiveResource,
                        action: action,
                        data: data,
                        changeset: Ash.Changeset.for_update(data, :update, %{name: "Other"})
                      })
           end) =~ "publication condition raised"

    publish = Ash.Resource.Info.action(ReactiveResource, :publish)
    refute Notifier.requires_original_data?(ReactiveResource, action)
    assert Notifier.requires_original_data?(ReactiveResource, publish)
  end

  defp no_bus_notification do
    %Notification{
      resource: NoBusResource,
      action: Ash.Resource.Info.action(NoBusResource, :create),
      data: %NoBusResource{id: Ash.UUID.generate(), name: "Name"}
    }
  end
end
