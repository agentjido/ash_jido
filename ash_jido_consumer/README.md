# AshJido consumer fixture

This application tests AshJido version 3 with AshPostgres.

It covers:

- domain code-interface compilation
- Jido Exec and Jido Flow execution
- Ash policies and namespaced context
- attribute multitenancy
- relationship loads and safe serialization
- notifier publications to Jido Signal Bus
- redacted database errors
- atomic persistence compare-and-swap under concurrent writes

## Database

The defaults are:

- host: `127.0.0.1`
- port: `5432`
- user: `postgres`
- password: `postgres`
- database: `ash_jido_consumer_test`

Use the `ASH_JIDO_CONSUMER_DB_HOST`, `ASH_JIDO_CONSUMER_DB_PORT`, `ASH_JIDO_CONSUMER_DB_USER`, `ASH_JIDO_CONSUMER_DB_PASS`, and `ASH_JIDO_CONSUMER_DB_NAME` environment variables to change them.

## Run

```bash
cd ash_jido_consumer
mix setup
mix test
```

The fixture depends on the parent AshJido checkout. Its Jido dependencies resolve from published Hex packages through the parent package.
