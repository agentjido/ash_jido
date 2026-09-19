defmodule AshJido.SignalFactoryTest do
  use ExUnit.Case, async: true

  alias Ash.Notifier.Notification
  alias AshJido.Publication
  alias AshJido.SignalFactory
  alias AshJido.Test.ReactiveResource

  defp notification(data, options \\ []) do
    action = Ash.Resource.Info.action(ReactiveResource, Keyword.get(options, :action, :create))

    %Notification{
      resource: ReactiveResource,
      action: action,
      data: data,
      actor: Keyword.get(options, :actor),
      changeset: Keyword.get(options, :changeset)
    }
  end

  defp publication(options) do
    struct!(Publication, Keyword.merge([actions: [:create], signal_type: "test.created"], options))
  end

  test "builds all, selected, and primary-key payloads" do
    data = %ReactiveResource{id: "id-1", name: "Name", status: :draft, secret: "hidden"}

    assert {:ok, all} = SignalFactory.from_notification(notification(data), publication(include: :all))
    assert all.type == "test.created"
    assert all.source == "/ash/reactive_resource/create/create"
    assert all.subject == "/reactive_resource/id-1"
    assert all.data.name == "Name"
    refute Map.has_key?(all.data, :secret)

    assert {:ok, selected} =
             SignalFactory.from_notification(notification(data), publication(include: [:name]))

    assert selected.data == %{name: "Name"}

    assert {:ok, primary_key} =
             SignalFactory.from_notification(notification(data), publication(include: :primary_key))

    assert primary_key.data == %{id: "id-1"}
  end

  test "supports nil data and metadata from an Ash changeset" do
    assert {:ok, signal} =
             SignalFactory.from_notification(notification(nil), publication(include: :all))

    assert signal.data == %{}
    assert signal.subject == nil

    old = %ReactiveResource{id: "id-2", name: "Old", status: :draft}

    changeset =
      old
      |> Ash.Changeset.for_update(:update, %{name: "New"})
      |> Ash.Changeset.set_tenant("tenant-1")

    current = %{old | name: "New"}

    publication =
      publication(
        include: :changes_only,
        metadata: [:actor, :tenant, :changes, :previous_state]
      )

    assert {:ok, signal} =
             SignalFactory.from_notification(
               notification(current, changeset: changeset, actor: %{"id" => "actor-1"}),
               publication
             )

    assert signal.data.name == "New"
    assert signal.data.ash_jido.actor_id == "actor-1"
    assert signal.data.ash_jido.tenant == "tenant-1"
    assert signal.data.ash_jido.changes == %{name: "New"}
    assert signal.data.ash_jido.previous_state.name == "Old"
  end

  test "handles missing fields, string keys, and metadata without a changeset" do
    assert {:ok, selected} =
             SignalFactory.from_notification(notification(nil), publication(include: [:name]))

    assert selected.data == %{}

    assert {:ok, primary_key} =
             SignalFactory.from_notification(notification(nil), publication(include: :pkey_only))

    assert primary_key.data == %{}

    string_data = %{"id" => nil, "name" => "String Name"}

    assert {:ok, signal} =
             SignalFactory.from_notification(
               notification(string_data, actor: "system"),
               publication(
                 include: [:name, :missing],
                 metadata: [:actor, :tenant, :changes, :previous_state]
               )
             )

    assert signal.subject == nil
    assert signal.data.name == "String Name"
    refute Map.has_key?(signal.data, :missing)

    assert signal.data.ash_jido == %{
             actor_id: "system",
             changes: %{},
             previous_state: nil
           }
  end
end
