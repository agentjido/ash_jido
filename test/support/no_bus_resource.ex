defmodule AshJido.Test.NoBusResource do
  @moduledoc false

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
    attribute(:name, :string, allow_nil?: false)
  end

  actions do
    create :create do
      accept([:name])
    end
  end

  jido do
    publish(:create)
  end
end
