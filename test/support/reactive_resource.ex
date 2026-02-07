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
    attribute(:name, :string, allow_nil?: false)

    attribute :status, :atom do
      default(:draft)
      constraints(one_of: [:draft, :published, :archived])
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
      change(set_attribute(:status, :published))
    end

    update :internal_update do
      accept([:secret])
    end
  end

  jido do
    signal_bus(:ash_jido_test_bus)
    signal_prefix("test")

    publish(:create, "test.resource.created",
      include: [:id, :name, :status],
      metadata: [:actor, :tenant]
    )

    publish(:publish, "test.resource.published",
      include: [:id, :status],
      metadata: [:actor, :changes]
    )

    publish(:update, "test.resource.conditional",
      include: [:id, :status],
      condition: fn notification ->
        notification.data && notification.data.status == :published
      end
    )

    publish_all(:update, include: :changes_only)
  end
end
