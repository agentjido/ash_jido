# AshJido consolidated Jido V3 upgrade plan

Date: 2026-11-14. Assignment: U1, Ash. Status: checked source plan; implementation is not started.

## Authority and boundary

This plan permits no implementation, dependency installation, branch switch, database migration, commit, push, PR, or release. The coordinator owns integration in Jidoka. Preserve unrelated work. Do not edit `CHANGELOG.md`.

This is a breaking consumer migration to one consolidated `:jido` application. No split `:jido_action`, `:jido_signal`, or `:jido_ai` application may remain in the active graph. Do not copy core modules into AshJido. No stored-data change is authorized.

## Recorded sources and baseline

Before this plan write, the local origin was `git@github.com:agentjido/ash_jido.git`, branch `main`, HEAD `7257572f782d64d2c30be9f8d787c3ed7182b1dd`. `git status --short` was empty. No `docs/ROLE.md` was present. Read the workspace and package `AGENTS.md` files. The package instructions contain older architecture and dependency text; the release source governs this audit.

GitHub `release/v3` and local `origin/release/v3` both resolve to `0c522017e509a7eebb9d70c303bf0a44794701d9`. **Use this exact release commit as the implementation baseline**, on a new work branch after implementation authorization. Do not start from local main. Its comparison with the release branch covers 121 files, with 5,612 additions and 12,271 deletions. The release branch adds the required persistence adapter and replaces much of the V2 generation, schema, signal, and test code. Preserve this work.

The shared target is `agentjido/jido`, revision `05723b96c6ead47dec04fe69b1c34ad62f999c54`. Its manifest declares version `3.0.0-beta.2`, Elixir `~> 1.18`, Zoi `~> 0.19.0`, ReqLLM `~> 1.30`, and Runic `~> 0.1.0-alpha.13`. The local Jido working tree is at `15698ccc2f644bfab0c18433a594049c3a16fa9a`; it was not used as the target. The exact target Git object is available locally. Source inspection used an archive of that object. GitHub also accepted the exact target tree request.

The release lock pins Jido `bdd610e92f9f4f4d7cf554f158db51d16beecc40`, split Action `ae7266893c9eb47b10a4c2f711bdc517abf269ac`, split Signal `7b825f1d050a0e0159bb2a72ba79c100b5d362d3`, Zoi 0.18.11, and Runic alpha.12. These are not target-compatible proof.

## Required file and API changes

| Files on the release baseline | Source finding and required work |
| --- | --- |
| `mix.exs`, `mix.lock` | Pin only Jido to the shared exact Git ref. Remove split Action and Signal declarations and lock entries. Change direct Zoi to `~> 0.19.0`. Keep the Ash constraint `~> 3.31 and >= 3.34.4`. Resolve the new core closure, including ReqLLM and Runic. |
| `lib/ash_jido/persistence/adapter.ex` | Change `@behaviour Jido.Persistence.Adapter` to `Jido.Persistence.Store`. The old behavior module does not exist at the target. Store requires `validate_options/1`, `get/2`, `compare_and_swap/4`, and `delete/2`; `put/3` and `scan/4` are optional. The existing callback arities match. Do not add scan for this migration. |
| `lib/ash_jido/error.ex` | Replace the removed `Jido.Action.Error` alias with `Jido.Error`. Its validation, execution, timeout, and internal constructors accept a map or keyword options. Preserve redacted messages and `details.reason` values. |
| `test/ash_jido/error_test.exs`, `test/integration/v3_exec_test.exs`, `ash_jido_consumer/test/integration/v3_integration_test.exs` | Replace old `Jido.Action.Error.*` struct assertions with target `Jido.Error` categories, including `ExecutionError` and `ValidationError`. Verify exact error details through Exec, not only constructor calls. |
| `lib/ash_jido/generator.ex`, `schema.ex`, `type_mapper.ex`, `runtime.ex` | Keep generated static input and output schemas, `on_before_validate_params/1`, and `run/2`. These callbacks still exist. Target Joi schemas are Zoi schemas, so a complete schema rewrite is not required. Check Zoi 0.19 parsing, named refinement MFAs, required/null/default behavior, unknown keys, and output validation. Use `Jido.Exec.run/4` for the checked action boundary. Keep the result/page/metadata envelope, identity selection, and Ash context authorization. Change code only where a target contract test fails. |
| `lib/ash_jido/signal_factory.ex`, `notifier.ex`, publication transformer | Target `Jido.Signal.new/1`, Bus `publish/2`, and `subscribe/3` exist. Preserve explicit publication types, public field selection, private field removal, scalar CloudEvents extensions, and structured metadata under `data.ash_jido`. Verify one notification produces one signal. |
| `ash_jido_consumer/test/integration/persistence_test.exs` | Change the Counter definition from `agent do schema(...) end` to target `state do schema(...) end`. Replace `Counter.new!` with `Counter.instantiate!` or `Jido.Agent.instantiate!`. Target generated modules expose `instantiate!/1`, not `new!/1`. Keep the save/load/delete round trip and revision checks. |
| `ash_jido_consumer/mix.lock` | Resolve the existing intentional parent path dependency against the upgraded parent. Remove obsolete split applications from this separate lock too. No new direct core override is needed unless source resolution proves a conflict. |
| `guides/persistence.md`, `guides/v3-migration.md`, `guides/flow.md`, `README.md`, `usage-rules.md`, package instructions | Correct changed behavior names, constructors, Agent DSL examples, and source guidance. `ASH_JIDO_V3_PLAN.md` contains the old behavior name; mark its old contract as superseded by this plan. Do not present the older plan as current API proof. |

The release branch removes `SensorDispatchBridge`, `SignalEmitter`, and the old tools wrapper. Do not restore them. Signal delivery uses the native bus. No release runtime source calls `Jido.Sensor`; native sensor consumers are outside this package test boundary.

## Persistence invariants and stop gates

The release adapter stores binary `key`, `value`, and `write_token` fields. The store transformer makes these private and required, with a binary key primary key and an atomic update action. Preserve the generated private action names: Jidoka reads through `:ash_jido_persistence_read` directly.

Target `Jido.Persistence.Store` accepts `{:ok, bytes, token}` and converts the opaque token to the `{:token, token}` write condition. Existing Ash reads match this contract. Preserve all three write conditions: `:not_found`, exact prior bytes, and `{:token, token}`. A successful write must replace the token even when bytes do not change. A stale write must return `{:error, :conflict}` without a write. Keep atomic `Ash.bulk_update` with `strategy: [:atomic]`; never replace it with read then write.

Keep `authorize?: false` fixed for this infrastructure resource. Preserve tenant, domain, context, and timeout options. Check missing-row deletion, same-value writes, duplicate insert, concurrent token writers, and ABA sequences. Classify errors as rejected only before a write starts; retain indeterminate outcomes after a write may have started. Review the current message-based duplicate-insert classification with actual backend errors.

The existing ETS tests and Postgres consumer tests do not prove SQLite or durable commit behavior. The Postgres consumer uses an SQL Sandbox outer transaction. Target core Ecto storage rejects outer transactions for writes. This does not itself impose a new Ash callback, but it identifies a durability risk: add an isolated, non-sandbox Postgres check for committed writes and inspect Ash transaction behavior. If a conforming fix changes supported transaction semantics or stored data, stop and return the exact change for approval. Do not change schema columns, key format, record bytes, tombstone meaning, or codec versions in this unit.

Jidoka selects both AshPostgres and AshSqlite for `Jidoka.Storage.Checkpoints.Record`. It owns those backend checks and data-layer configuration. Do not replace the Ash adapter with core Ecto storage merely because it exists.

## Unit order and source strategy

1. Prepare the exact release baseline and an isolated target Jido checkout after authorization. Keep the current local Jido tree intact.
2. Change source declarations and resolve the single-core graph. Then change the behavior and error APIs.
3. Check generated actions, schemas, errors, and publications with ETS. Then check Store through the public wrapper.
4. Update and check the Postgres consumer. Hand the checked candidate to the coordinator for SQLite, Postgres, and Jidoka lifecycle checks.
5. Run package quality checks and review both locks. Release order, if later authorized: target Jido, AshJido, then Jidoka. Browser has no dependency on AshJido and can proceed independently.

For local development, a temporary `path:` override can select an isolated Jido tree whose HEAD is exactly the shared target and whose status is recorded. The existing sibling Jido path is not sufficient. Use separate build and dependency directories for this trial. Remove temporary source edits before portable checks.

For portable verification, declare `{:jido, github: "agentjido/jido", ref: "05723b96c6ead47dec04fe69b1c34ad62f999c54"}`. Retain an override only if the actual combined graph requires it. Use registry Zoi 0.19 and the target's declared Runic source. Regenerate only the changed dependency closure; do not delete the whole lock or update all dependencies. Check in neither a temporary path nor a hidden fork. Resolve and inspect both package and consumer locks. Future Hex constraints must follow a separately verified compatible release; a version string alone does not prove this exact source contract.

## Exact future checks

These commands are supported by the release manifest and test paths. They were not run in this planning phase. Run from the package root with Elixir 1.18 or compatible and the approved OTP baseline. Dependency resolution is a future authorized step.

```sh
mix deps.get
mix deps.tree
mix compile --warnings-as-errors
mix test test/ash_jido/v3_compiler_test.exs test/ash_jido/type_mapper_test.exs test/ash_jido/error_test.exs test/ash_jido/query_params_test.exs test/ash_jido/serializer_test.exs
mix test test/integration/v3_exec_test.exs test/integration/flow_test.exs
mix test test/ash_jido/signal_factory_test.exs test/ash_jido/notifier_test.exs test/integration/signal_test.exs
mix test test/ash_jido/persistence_adapter_test.exs
mix test
mix quality
```

Extend `persistence_adapter_test.exs` to call `Jido.Persistence.Store.open/1`, `read/2`, and `compare_and_swap/4`. Include a Jido save/load revision and tombstone round trip with ETS. This proves the new behavior through the owning boundary.

From `ash_jido_consumer/`, after selection of a disposable test database:

```sh
mix deps.get
mix deps.tree
mix compile --warnings-as-errors
ASH_JIDO_CONSUMER_DB_NAME=ash_jido_u1_consolidated_v3_test MIX_ENV=test mix test test/integration/persistence_test.exs test/integration/v3_integration_test.exs
```

The consumer test alias creates and migrates its selected database. Do not run it against user data. Host, port, user, and password are selected by `ASH_JIDO_CONSUMER_DB_HOST`, `ASH_JIDO_CONSUMER_DB_PORT`, `ASH_JIDO_CONSUMER_DB_USER`, and `ASH_JIDO_CONSUMER_DB_PASS`. Add the non-sandbox durability scenario to this consumer before the final storage verdict. No migration was run during planning.

Repeat compile and focused tests with portable source resolution in a clean environment. Inspect `mix deps.tree`, locks, and compile paths: exactly one provider must own core, Action, Signal, and AI modules. No split core application may remain, even if Mix reports no version conflict.

## Readiness, blockers, and coverage

**Verdict: ready for a bounded implementation; not compatible as currently declared.** No missing required core API was found: Store, Error, Action, Exec, Flow, Signal, and Agent construction have target replacements. No core change is proposed. Backend conformance and stored-data equivalence remain hard completion gates. A failure that requires new data meaning or transaction behavior must return to the coordinator.

First safe implementation unit: prepare the recorded release baseline, change only the dependency sources, Store behavior, Error alias, and obsolete test constructors/assertions. Resolve the graph, compile, and run the listed ETS boundary tests. Keep all existing storage fields and write semantics. Return any backend durability failure separately; it does not block these source and API repairs. Wait for the coordinator's bounded assignment before this unit starts.

No compile, test, quality check, dependency install, or consumer run occurred. Affected but untested consumers: the bundled Postgres consumer, Jidoka with Postgres, Jidoka with SQLite, and native bus/sensor callers outside this package. Other ecosystem consumers were not inventoried or tested. No workspace-wide compatibility claim is made.

## Source index

- [Canonical coordinator plan](../../../../docs/plans/2026-11-14-0821-jidoka-consolidated-v3-plan.md).
- [Ash release source](https://github.com/agentjido/ash_jido/tree/0c522017e509a7eebb9d70c303bf0a44794701d9): paths named above, including manifests, locks, test helpers, and consumer configuration.
- [Target Jido source](https://github.com/agentjido/jido/tree/05723b96c6ead47dec04fe69b1c34ad62f999c54): `mix.exs`, `lib/jido/persistence/store.ex`, `lib/jido/persistence.ex`, `lib/jido/persistence/ecto.ex`, `lib/jido/error.ex`, `lib/jido/action.ex`, `lib/jido/exec.ex`, `lib/jido/joi.ex`, `lib/jido/agent.ex`, `lib/jido/agent/dsl.ex`, `lib/jido/signal.ex`, and `lib/jido/signal/bus.ex`.
- Jidoka source inspected read-only: `lib/jidoka/storage/checkpoints.ex`, `lib/jidoka/storage/checkpoints/record.ex`, runtime calls, and `mix.exs`.
