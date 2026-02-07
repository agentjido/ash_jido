defmodule AshJido.Test.SelectiveResource do
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
    attribute(:secret, :string)
  end

  actions do
    defaults([:read])

    create :create do
      accept([:name])
    end

    update :internal_update do
      accept([:secret])
    end
  end

  jido do
    signal_bus(:ash_jido_test_bus)
    signal_prefix("test")

    publish(:create, "test.selective.created", include: [:id, :name])
  end
end
