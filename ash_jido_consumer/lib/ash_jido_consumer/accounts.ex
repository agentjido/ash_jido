defmodule AshJidoConsumer.Accounts do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshJidoConsumer.Accounts.User)
  end
end
