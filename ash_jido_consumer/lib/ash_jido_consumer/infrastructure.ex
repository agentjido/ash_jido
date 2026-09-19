defmodule AshJidoConsumer.Infrastructure do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshJidoConsumer.Infrastructure.JidoStore)
  end
end
