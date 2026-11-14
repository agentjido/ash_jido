# AshJido local upgrade results

Date: 2026-11-14. Owner: U1. Integration owner: Jidoka coordinator.

## Source state

- Path: `/Users/mhostetler/Source/Jido/jido_adapters/ash_jido`.
- Origin: `git@github.com:agentjido/ash_jido.git`.
- Initial task branch: `upgrade/consolidated-v3`; final delivery uses `release/v3`.
- HEAD and release baseline: `0c522017e509a7eebb9d70c303bf0a44794701d9`.
- Final core source: `agentjido/jido`, exact revision `047bf746330a2fbe7c3b25c045552e0303c97eaf`. Verified in the installed dependency checkout. The initial migration used `05723b96c6ead47dec04fe69b1c34ad62f999c54`.
- Toolchain: Elixir 1.20.4, Erlang/OTP 29.1.2.
- Initial checks were local. The migration was then committed and pushed to `release/v3`. The earlier local plan was preserved. Only assignment files changed.

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

Temporary logs used for the initial check: `/tmp/u1-ash_jido-compile.log`, `/tmp/u1-ash_jido-test.log`, `/tmp/u1-ash_jido-quality.log`, `/tmp/u1-ash_jido-tree.log`, `/tmp/u1-ash-consumer-compile.log`, and `/tmp/u1-ash-consumer-test.log`.

## Return

The local package is ready for Jidoka compile and isolated integration checks. All required package checks passed. There is no package compile or API blocker. SQLite, existing checkpoint data, Jidoka lifecycle behavior, and native sensor consumers were not tested here. Live production behavior is not claimed.

See the [source audit and plan](2026-11-14-consolidated-v3-upgrade.md). The coordinator authorized local implementation after that planning phase.

## Checkpoint fix and cleanup follow-up

The coordinator published the core checkpoint fix at `047bf746330a2fbe7c3b25c045552e0303c97eaf`. It makes Joi field order deterministic and retains strict code-change fingerprint checks. This package now pins that exact source. Only the core Git revision changed in dependency resolution; registry versions remain unchanged.

Final checks against this exact source: `mix deps.get` exited 0; `mix test` exited 0 with 44 package tests and 10 isolated PostgreSQL integration tests. The PostgreSQL command is the same isolated command in the table above. `mix quality` exited 0, including warnings-as-errors compile, format, configured Credo checks, Dialyzer, and Doctor. The coordinator owns independent rebuild regression tests and the combined Jidoka check.

Both original plan documents are committed. The temporary inspection archives `/tmp/u1-ash`, `/tmp/u1-browser`, `/tmp/u1-core`, the backup `/tmp/u1-preserved-plans`, and task-only `/tmp/u1-*` source snippets and logs can be removed after this follow-up is published. The package source, tests, exact sources, check commands, counts, and CI limits are preserved in these documents and Git history. Keep primary checkouts, existing main branches, dependencies, build data, and the isolated test database. No additional Git worktree was created for either package. The task branch can be deleted after its full history is reachable from the published `release/v3` branch.

Initial published migration: `081eb345a865e914d54ec11c15ed7daa8a0d3cde`. [CI run 43609792052](https://github.com/agentjido/ash_jido/actions/runs/43609792052) passed compilation, the four test jobs, and code quality checks. The audit failed on unchanged Ash 3.37.0 advisories `CVE-2026-96581` and `CVE-2026-114214`; Hex packaging was skipped. No audit gate was changed. These dependency advisories remain outside this core compatibility fix.
