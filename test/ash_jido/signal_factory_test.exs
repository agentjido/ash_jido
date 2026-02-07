defmodule AshJido.SignalFactoryTest do
  use ExUnit.Case, async: true

  alias Ash.Notifier.Notification
  alias AshJido.Publication
  alias AshJido.SignalFactory

  describe "from_notification/2" do
    test "creates signal with auto-derived type" do
      notification = build_notification(:create, base_record(%{id: "123", name: "Test"}))
      publication = %Publication{actions: [:create], include: :all, metadata: []}

      assert {:ok, signal} = SignalFactory.from_notification(notification, publication)
      assert signal.type == "test.reactive_resource.create"
      assert signal.data.id == "123"
      assert signal.data.name == "Test"
    end

    test "creates signal with explicit type override" do
      notification = build_notification(:create, base_record(%{id: "123"}))

      publication = %Publication{
        actions: [:create],
        signal_type: "custom.domain.created",
        include: :pkey_only,
        metadata: []
      }

      assert {:ok, signal} = SignalFactory.from_notification(notification, publication)
      assert signal.type == "custom.domain.created"
    end

    test "pkey_only includes only primary key" do
      notification =
        build_notification(
          :create,
          base_record(%{id: "123", name: "Test", secret: "hidden"})
        )

      publication = %Publication{actions: [:create], include: :pkey_only, metadata: []}

      assert {:ok, signal} = SignalFactory.from_notification(notification, publication)
      assert signal.data == %{id: "123"}
      refute Map.has_key?(signal.data, :name)
      refute Map.has_key?(signal.data, :secret)
    end

    test "changes_only includes only changed attributes" do
      previous = base_record(%{id: "123", status: :draft, name: "Old"})
      changeset = Ash.Changeset.for_update(previous, :update, %{status: :published})
      updated = base_record(%{id: "123", status: :published, name: "Old"})
      notification = build_notification(:update, updated, changeset: changeset)
      publication = %Publication{actions: [:update], include: :changes_only, metadata: []}

      assert {:ok, signal} = SignalFactory.from_notification(notification, publication)
      assert signal.data == %{status: :published}
    end

    test "explicit field list filters attributes" do
      notification =
        build_notification(
          :create,
          base_record(%{id: "123", name: "Test", secret: "hidden"})
        )

      publication = %Publication{actions: [:create], include: [:id, :name], metadata: []}

      assert {:ok, signal} = SignalFactory.from_notification(notification, publication)
      assert signal.data == %{id: "123", name: "Test"}
      refute Map.has_key?(signal.data, :secret)
    end

    test "includes actor_id when :actor in metadata" do
      notification =
        build_notification(
          :create,
          base_record(%{id: "123"}),
          actor: %{id: "user-456"}
        )

      publication = %Publication{actions: [:create], include: :pkey_only, metadata: [:actor]}

      assert {:ok, signal} = SignalFactory.from_notification(notification, publication)
      assert signal_metadata(signal).actor_id == "user-456"
    end

    test "includes tenant when :tenant in metadata" do
      changeset =
        Ash.Changeset.for_create(
          AshJido.Test.ReactiveResource,
          :create,
          %{name: "Test"},
          tenant: "org_abc"
        )

      notification =
        build_notification(
          :create,
          base_record(%{id: "123"}),
          changeset: changeset
        )

      publication = %Publication{actions: [:create], include: :pkey_only, metadata: [:tenant]}

      assert {:ok, signal} = SignalFactory.from_notification(notification, publication)
      assert signal_metadata(signal).tenant == "org_abc"
    end

    test "source URI follows /ash/{resource}/{type}/{name} pattern" do
      notification = build_notification(:create, base_record(%{id: "123"}))
      publication = %Publication{actions: [:create], include: :pkey_only, metadata: []}

      assert {:ok, signal} = SignalFactory.from_notification(notification, publication)
      assert signal.source == "/ash/reactive_resource/create/create"
    end

    test "subject identifies specific record" do
      notification = build_notification(:create, base_record(%{id: "abc-123"}))
      publication = %Publication{actions: [:create], include: :pkey_only, metadata: []}

      assert {:ok, signal} = SignalFactory.from_notification(notification, publication)
      assert signal.subject == "/reactive_resource/abc-123"
    end
  end

  defp build_notification(action_name, data, opts \\ []) do
    %Notification{
      resource: AshJido.Test.ReactiveResource,
      action: Ash.Resource.Info.action(AshJido.Test.ReactiveResource, action_name),
      data: data,
      changeset: Keyword.get(opts, :changeset),
      actor: Keyword.get(opts, :actor),
      metadata: %{}
    }
  end

  defp base_record(attrs) do
    defaults = %{id: "base-id", name: "Name", status: :draft, secret: "secret"}
    struct(AshJido.Test.ReactiveResource, Map.merge(defaults, attrs))
  end

  defp signal_metadata(signal) do
    Map.get(signal, :jido_metadata) ||
      signal
      |> Map.get(:extensions, %{})
      |> Map.get("jido_metadata", %{})
  end
end
