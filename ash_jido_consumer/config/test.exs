import Config

db_port =
  "ASH_JIDO_CONSUMER_DB_PORT"
  |> System.get_env("5432")
  |> String.to_integer()

config :ash_jido_consumer, AshJidoConsumer.Repo,
  username: System.get_env("ASH_JIDO_CONSUMER_DB_USER", "postgres"),
  password: System.get_env("ASH_JIDO_CONSUMER_DB_PASS", "postgres"),
  hostname: System.get_env("ASH_JIDO_CONSUMER_DB_HOST", "127.0.0.1"),
  port: db_port,
  database: System.get_env("ASH_JIDO_CONSUMER_DB_NAME", "ash_jido_consumer_test"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  show_sensitive_data_on_connection_error: true,
  stacktrace: true

config :logger, level: :warning
