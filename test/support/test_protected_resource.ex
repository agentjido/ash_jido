defmodule AshJido.Test.ProtectedResource do
  @moduledoc """
  Test resource with Ash policies to verify AshJido respects authorization.
  """

  use Ash.Resource,
    domain: nil,
    extensions: [AshJido],
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, allow_nil?: false, public?: true)
    attribute(:owner_id, :string, public?: true)
    timestamps()
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:title, :owner_id])
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if(actor_present())
    end

    policy action_type(:read) do
      authorize_if(always())
    end

    policy action_type(:destroy) do
      authorize_if(actor_present())
    end
  end

  jido do
    action(:create, name: "create_protected")
    action(:read, name: "list_protected")
    action(:destroy, name: "delete_protected")
  end
end
