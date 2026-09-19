defmodule AshJido.Test.ReactiveResource do
  @moduledoc false

  use Ash.Resource,
    domain: AshJido.Test.ReactiveDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshJido],
    notifiers: [AshJido.Notifier]

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)

    attribute :status, :atom do
      default(:draft)
      constraints(one_of: [:draft, :published, :archived])
      public?(true)
    end

    attribute(:secret, :string)
    timestamps()
  end

  actions do
    defaults([:read])

    create :create do
      accept([:name, :status, :secret])
    end

    update :update do
      accept([:name, :status])
    end

    update :publish do
      require_atomic?(false)
      change(set_attribute(:status, :published))
    end

    update :internal_update do
      accept([:secret])
    end
  end

  jido do
    action(:create, name: "create_reactive")
    signal_bus(:ash_jido_test_bus)

    publish(:create, "test.resource.created",
      include: [:id, :name, :status],
      metadata: [:actor, :tenant]
    )

    publish(:publish, "test.resource.published",
      include: [:id, :status],
      metadata: [:actor, :changes, :previous_state]
    )

    publish(:update, "test.resource.conditional",
      include: [:id, :status],
      condition: fn notification ->
        notification.data && notification.data.status == :published
      end
    )

    publish(:update, "test.resource.condition_error",
      include: [:id],
      condition: fn _notification -> raise "expected test condition failure" end
    )

    publish(:internal_update, "test.resource.internal_updated", include: :changes_only)
  end
end
