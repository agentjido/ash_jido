defmodule AshJidoConsumer.Infrastructure.JidoStore do
  use Ash.Resource,
    domain: AshJidoConsumer.Infrastructure,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJido]

  postgres do
    table("jido_store")
    repo(AshJidoConsumer.Repo)
  end

  jido do
    persistence_store()
  end
end
