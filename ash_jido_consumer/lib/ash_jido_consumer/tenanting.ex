defmodule AshJidoConsumer.Tenanting do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshJidoConsumer.Tenanting.Note)
  end
end
