defmodule AshJido.Test.MultiJidoItem do
  @moduledoc """
  Regression fixture for agentjido/ash_jido#19.

  Declares two `jido` entries that both target the same underlying Ash
  `:read` action, distinguished by their `name:` metadata and explicit
  `module_name:` values. Verifies that the generator produces one
  distinct Jido action module per entry without changing the default
  module naming contract for single-entry actions.
  """

  use Ash.Resource,
    domain: nil,
    extensions: [AshJido],
    data_layer: Ash.DataLayer.Ets

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, allow_nil?: false)
    attribute(:status, :string, default: "active")
    timestamps()
  end

  actions do
    defaults([:read])

    create :create do
      accept([:title, :status])
    end
  end

  jido do
    action(:read,
      name: "list_multi_items",
      module_name: AshJido.Test.MultiJidoItem.Jido.ListMultiItems,
      description: "List all multi items"
    )

    action(:read,
      name: "get_multi_item",
      module_name: AshJido.Test.MultiJidoItem.Jido.GetMultiItem,
      description: "Get one multi item",
      query_params?: true
    )
  end
end
