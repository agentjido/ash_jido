defmodule AshJidoConsumer.Tenanting.Note do
  use Ash.Resource,
    domain: AshJidoConsumer.Tenanting,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("tenant_notes")
    repo(AshJidoConsumer.Repo)
  end

  multitenancy do
    strategy(:attribute)
    attribute(:tenant_id)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:tenant_id, :string, allow_nil?: false, public?: true)
    attribute(:body, :string, allow_nil?: false, public?: true)
    timestamps()
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:body])
    end
  end
end
