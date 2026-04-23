defmodule AshJido.NotifierTest do
  use ExUnit.Case, async: false

  alias Ash.Notifier.Notification
  alias AshJido.Notifier

  @moduletag :capture_log

  defmodule BusResolver do
    def bus, do: :ash_jido_test_bus
    def bad_bus, do: raise("bad bus")
  end

  defmodule MfaBusResource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshJido],
      notifiers: [AshJido.Notifier]

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
    end

    actions do
      defaults([:read])

      create :create do
        accept([:name])
      end
    end

    jido do
      signal_bus({AshJido.NotifierTest.BusResolver, :bus, []})
      publish(:create)
    end
  end

  defmodule InvalidMfaBusResource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshJido],
      notifiers: [AshJido.Notifier]

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
    end

    actions do
      defaults([:read])

      create :create do
        accept([:name])
      end
    end

    jido do
      signal_bus({AshJido.NotifierTest.BusResolver, :bad_bus, []})
      publish(:create)
    end
  end

  defmodule PreviousStateResource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshJido],
      notifiers: [AshJido.Notifier]

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
    end

    actions do
      defaults([:read])

      update :update do
        require_atomic?(false)
        accept([:name])
      end
    end

    jido do
      publish(:update, metadata: [:previous_state])
    end
  end

  test "returns :ok when no publications are configured" do
    notification =
      build_notification(
        AshJido.Test.User,
        :register,
        struct(AshJido.Test.User, %{id: "123", name: "Jane", email: "jane@example.com"})
      )

    assert :ok = Notifier.notify(notification)
  end

  test "publishes signals through a signal bus resolved by MFA" do
    start_supervised!({Jido.Signal.Bus, name: :ash_jido_test_bus})

    assert {:ok, _subscription_id} =
             Jido.Signal.Bus.subscribe(
               :ash_jido_test_bus,
               "**",
               dispatch: {:pid, target: self()}
             )

    notification =
      build_notification(
        MfaBusResource,
        :create,
        struct(MfaBusResource, %{id: "mfa-1", name: "MFA"})
      )

    assert :ok = Notifier.notify(notification)
    assert_receive {:signal, %Jido.Signal{type: "ash.mfa_bus_resource.create"}}, 500
  end

  test "logs error and returns :ok when signal bus MFA raises" do
    notification =
      build_notification(
        InvalidMfaBusResource,
        :create,
        struct(InvalidMfaBusResource, %{id: "bad-mfa-1", name: "MFA"})
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

  test "default publish update does not require original data for fully atomic changesets" do
    %{resource: resource, domain: domain} = compile_atomic_publication_modules()

    assert %Ash.Changeset{} =
             Ash.Changeset.fully_atomic_changeset(
               resource,
               :update,
               %{status: :published},
               domain: domain
             )
  end

  test "requires original data when publication metadata requests previous_state" do
    action = Ash.Resource.Info.action(PreviousStateResource, :update)

    assert Notifier.requires_original_data?(PreviousStateResource, action)
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

  defp compile_atomic_publication_modules do
    suffix = System.unique_integer([:positive])
    resource = Module.concat(AshJido.Test, :"AtomicPublishResource#{suffix}")
    domain = Module.concat(AshJido.Test, :"AtomicPublishDomain#{suffix}")

    source = """
    defmodule #{inspect(resource)} do
      use Ash.Resource,
        domain: #{inspect(domain)},
        validate_domain_inclusion?: false,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshJido],
        notifiers: [AshJido.Notifier]

      ets do
        private?(true)
      end

      attributes do
        uuid_primary_key(:id)

        attribute :status, :atom do
          default(:draft)
          constraints(one_of: [:draft, :published])
        end

        timestamps()
      end

      actions do
        defaults([:read])

        create :create do
          accept([:status])
        end

        update :update do
          accept([:status])
        end
      end

      jido do
        signal_bus(:ash_jido_test_bus)
        publish(:update)
      end
    end

    defmodule #{inspect(domain)} do
      use Ash.Domain,
        validate_config_inclusion?: false

      resources do
        resource(#{inspect(resource)})
      end
    end
    """

    Code.compile_string(source)

    %{resource: resource, domain: domain}
  end
end
