# Ash Jido Consumer

Single-app real integration harness for `ash_jido` using `AshPostgres`.

This app intentionally stays small and focused:
- one consumer app
- multiple domains/resources for scenario coverage
- real database-backed execution paths

## Scenarios Covered

- Ash context passthrough (`authorize?`, `scope`, `context`, `tracer`, `timeout`)
- actor-from-scope policy behavior and explicit actor override precedence
- relationship-aware read loads (`load`)
- Ash notifications to Jido signals (`emit_signals?` + runtime dispatch override)
- signal type/source overrides (`signal_type`, `signal_source`)
- signal dispatch failures that do not fail the primary write result
- mixed-dispatch paths (one success + one failure) with telemetry failure metadata
- Jido-namespaced telemetry (`telemetry?`)
- telemetry exception path (`[:jido, :action, :ash_jido, :exception]`)
- Jido action metadata and tool export helpers (`AshJido.Tools`)
- real DB constraint mapping (unique and foreign key violations)
- sensor bridge forwarding via `AshJido.SensorDispatchBridge`
- attribute multitenancy behavior (`tenant`-scoped create/read)

## Database Setup

Defaults (override with env vars):

- `ASH_JIDO_CONSUMER_DB_HOST` (default `127.0.0.1`)
- `ASH_JIDO_CONSUMER_DB_PORT` (default `5432`)
- `ASH_JIDO_CONSUMER_DB_USER` (default `postgres`)
- `ASH_JIDO_CONSUMER_DB_PASS` (default `postgres`)
- `ASH_JIDO_CONSUMER_DB_NAME` (default `ash_jido_consumer_test`)

## Run

```bash
cd ash_jido_consumer
mix setup
mix test
```

`mix test` runs `ecto.create` + `ecto.migrate` first via aliases.

Canonical guide:
- [AshPostgres Consumer Harness Walkthrough](../guides/walkthrough-ash-postgres-consumer.md)

## Coverage

`mix test --cover` is supported for this harness. Coverage output ignores generated `*.Jido.*` modules so nofile-generated code does not skew summary or fail reporting.
