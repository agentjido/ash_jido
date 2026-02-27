defmodule AshJidoConsumer.Content.Post do
  use Ash.Resource,
    domain: AshJidoConsumer.Content,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJido]

  postgres do
    table("posts")
    repo(AshJidoConsumer.Repo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, allow_nil?: false, public?: true)
    timestamps()
  end

  relationships do
    belongs_to(:author, AshJidoConsumer.Content.Author,
      allow_nil?: false,
      public?: true,
      attribute_public?: true
    )
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:title, :author_id])
    end

    update :update do
      accept([:title])
    end
  end

  jido do
    action(:create,
      emit_signals?: true,
      telemetry?: true,
      signal_type: "ash_jido_consumer.content.post.created",
      signal_source: "/ash_jido_consumer/content/post"
    )

    action(:read, load: [:author], telemetry?: true)
    action(:update, emit_signals?: true, telemetry?: true)
    action(:destroy, emit_signals?: true, telemetry?: true)
  end
end
