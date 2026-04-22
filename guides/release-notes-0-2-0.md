# Release Notes: 0.2.0 Preparation

This maintainer note captures the intended `0.2.0` release content before the
release workflow generates the final `CHANGELOG.md` entry.

`CHANGELOG.md` is intentionally not edited by normal PRs. CI enforces this so
`git_ops` can generate the final changelog from conventional commits during the
GitHub release workflow.

## Added

- Read-action query parameters for generated actions: `filter`, `sort`, `limit`,
  `offset`, and dynamic relationship `load`, with Ash safe input parsing and
  optional `max_page_size` bounds.
- Static resource-domain fallback, so generated actions use `context[:domain]`
  first and then the resource's configured `domain:` before raising.
- Public-surface schema generation that follows Ash `public?: true` inputs by
  default, with `include_private?: true` available for trusted/internal tool
  catalogs.
- `all_actions` expansion over public Ash actions by default, plus
  `only`/`except` filtering and trusted private-action opt-in.
- Resource notification publishing through `AshJido.Notifier`, `publish`, and
  `publish_all`, including configurable signal buses, prefixes, payload include
  modes, metadata, and predicates.
- Generated-action signal emission through `emit_signals?`, shared
  `AshJido.SignalFactory` payload construction, runtime `signal_dispatch`
  overrides, and signal delivery counters in telemetry metadata.
- Opt-in generated-action telemetry under the Jido namespace:
  `[:jido, :action, :ash_jido, :start | :stop | :exception]`.
- `AshJido.Tools` helpers for exporting generated action modules and
  LLM-friendly tool payloads.
- `AshJido.SensorDispatchBridge` helpers for forwarding dispatched signal
  messages into `Jido.Sensor.Runtime`.
- A real AshPostgres consumer harness under `ash_jido_consumer/` covering
  database-backed actions, policies, relationship loading, signals, and
  telemetry.
- Package quality infrastructure: shared GitHub Actions CI, docs and doctor
  checks, coverage enforcement, release workflow, Dependabot for Mix and GitHub
  Actions, and contributor docs.

## Changed

- Updated the dependency baseline to Elixir `~> 1.18`, Ash `~> 3.12`, Jido
  `~> 2.2`, `jido_action ~> 2.2`, `jido_signal ~> 2.1`, `splode ~> 0.3`, and
  `zoi ~> 0.17`.
- Split generated action runtime execution out of the compile-time generator
  into dedicated runtime/spec modules for clearer compile-time and runtime
  boundaries.
- Consolidated generated-action signal emission and notifier-driven
  publications around the same signal factory and dispatch accounting path.
- Documented explicit `module_name:` usage for intentionally exposing the same
  Ash action more than once.

## Fixed

- Update and destroy actions now use the resource's primary key fields instead
  of assuming a single `id` field.
- Destroy actions pass declared Ash destroy action arguments through to Ash.
- Non-map custom action results are wrapped so they satisfy `Jido.Exec` output
  validation.
- Multiple generated entries that would target the same module now fail at
  compile time with guidance to provide explicit `module_name:` values.
- README, guides, and usage rules now agree on naming, dependency compatibility,
  context resolution, query parameters, signals, telemetry, tools, and release
  tooling.

## Intentional Notes

- The final `CHANGELOG.md` entry, date, and tag should be produced by the GitHub
  release workflow.
- AshJido intentionally keeps the `AshJido` public module namespace for Ash DSL
  extension compatibility; no namespace migration is included in this release.
- The AshPostgres consumer harness remains a companion integration app, not part
  of the published Hex package files.
