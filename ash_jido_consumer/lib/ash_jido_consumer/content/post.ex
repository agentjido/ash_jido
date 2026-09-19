defmodule AshJidoConsumer.Content.Post do
  use Ash.Resource,
    domain: AshJidoConsumer.Content,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJido],
    notifiers: [AshJido.Notifier]

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
    action(:create)
    action(:read, load: [:author])
    action(:update)
    action(:destroy)

    signal_bus(:ash_jido_consumer_bus)

    publish(:create, "ash_jido_consumer.content.post.created",
      include: [:id, :title],
      metadata: [:actor]
    )

    publish(:update, "ash_jido_consumer.content.post.updated", include: [:id, :title])
    publish(:destroy, "ash_jido_consumer.content.post.destroyed", include: :pkey_only)
  end
end
