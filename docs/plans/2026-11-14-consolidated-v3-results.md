# AshJido local upgrade results

Date: 2026-11-14. Owner: U1. Integration owner: Jidoka coordinator.

## Source state

- Path: `/Users/mhostetler/Source/Jido/jido_adapters/ash_jido`.
- Origin: `git@github.com:agentjido/ash_jido.git`.
- Branch: `upgrade/consolidated-v3`.
- HEAD and release baseline: `0c522017e509a7eebb9d70c303bf0a44794701d9`.
- Core source: `agentjido/jido`, exact revision `05723b96c6ead47dec04fe69b1c34ad62f999c54`. Verified in the installed dependency checkout.
- Toolchain: Elixir 1.20.4, Erlang/OTP 29.1.2.
- No commit, push, PR, release, or core edit was made. The earlier local plan was preserved. Only assignment files changed.

## Changes

The package and consumer locks now use consolidated Jido, registry Zoi 0.19.0, and registry Runic 0.1.0-alpha.13. ReqLLM 1.30.0 and its required dependency closure were resolved. Split core declarations and lock entries were removed. Both formatter files now import consolidated Jido.

The public module remains `AshJido.Persistence.Adapter`. Only its behavior changed to `Jido.Persistence.Store`. `AshJido.Error` uses `Jido.Error`. Tests use current error categories, `Jido.Exec.compile/2`, Agent `state` sections, `instantiate!/1`, and explicit test namespaces.

Added tests cover the public Store token wrapper, ABA stale writes, checkpoint revision conflicts, tombstones, and committed Postgres writes after a connection returns to the pool. The existing suite covers generated actions, Flow, redaction, publications, same-value token replacement, and concurrent stale writers.

No persistence attribute, private action name, byte comparison, atomic query, token algorithm, authorization option, or adapter byte meaning changed. No existing checkpoint records were converted. Core fmt1-to-fmt3 compatibility is not proved by these isolated tests and remains with the integration owner.

## Checks

All commands below ran from the package root unless stated otherwise.

| Command | Exit | Result |
| --- | --- | --- |
| `mix deps.update zoi runic req_llm splode nimble_options` | 0 | Required core closure resolved. |
| `mix deps.get` | 0 | Exact Git core and registry dependencies installed. |
| `mix compile --warnings-as-errors` | 0 | Package compiled against the exact target. |
| `mix test` | 0 | 44 tests passed. No flaky tests were included by the package alias. |
| `mix deps.tree` | 0 | No split core application. |
| `mix quality` | 0 | Format, warnings-as-errors compile, configured Credo checks, Dialyzer, and Doctor passed. |
| `git diff --check` | 0 | No whitespace error. |

From `ash_jido_consumer/`:

| Command | Exit | Result |
| --- | --- | --- |
| `mix deps.update jido zoi runic req_llm splode nimble_options` | 0 | Consumer lock migrated. |
| `mix deps.get` | 0 | Remaining locked dependencies installed. |
| `mix compile --warnings-as-errors` | 0 | Consumer compiled. |
| `ASH_JIDO_CONSUMER_DB_NAME=ash_jido_u1_consolidated_v3_test MIX_ENV=test mix test test/integration/persistence_test.exs test/integration/v3_integration_test.exs` | 0 | 10 tests passed. Includes a non-sandbox committed-write check. |

The test alias created and migrated only `ash_jido_u1_consolidated_v3_test`. The committed-write test used a UUID key and removed only that key. No user database was reset. Dependency compile warnings from third-party packages were visible during initial builds; the package and consumer warnings-as-errors commands passed.

The active dev compile paths contain exactly one copy of each checked module: `Jido`, `Jido.Action`, `Jido.Signal`, and `Jido.AI`, all under the `jido` application. No temporary core path or fork is used. The consumer retains its intentional `path: ".."` source for this local package.

Logs: `/tmp/u1-ash_jido-compile.log`, `/tmp/u1-ash_jido-test.log`, `/tmp/u1-ash_jido-quality.log`, `/tmp/u1-ash_jido-tree.log`, `/tmp/u1-ash-consumer-compile.log`, and `/tmp/u1-ash-consumer-test.log`.

## Return

The local package is ready for Jidoka compile and isolated integration checks. All required package checks passed. There is no package compile or API blocker. SQLite, existing checkpoint data, Jidoka lifecycle behavior, and native sensor consumers were not tested here. Live production behavior is not claimed.

See the [source audit and plan](2026-11-14-consolidated-v3-upgrade.md). The coordinator authorized local implementation after that planning phase.
