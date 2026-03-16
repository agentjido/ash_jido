defmodule AshJidoConsumer.Content do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshJidoConsumer.Content.Author)
    resource(AshJidoConsumer.Content.Post)
  end
end
