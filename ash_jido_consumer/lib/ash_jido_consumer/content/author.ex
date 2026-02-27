defmodule AshJidoConsumer.Content.Author do
  use Ash.Resource,
    domain: AshJidoConsumer.Content,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("authors")
    repo(AshJidoConsumer.Repo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
    timestamps()
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:name])
    end
  end
end
