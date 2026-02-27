import Config

config :ash_jido_consumer, ecto_repos: [AshJidoConsumer.Repo]

config :ash_jido_consumer, AshJidoConsumer.Repo,
  migration_primary_key: [name: :id, type: :binary_id],
  migration_foreign_key: [column: :id, type: :binary_id]

import_config "#{config_env()}.exs"
