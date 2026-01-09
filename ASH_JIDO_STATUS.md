# AshJido Status Report

**Date**: 2026-01-09  
**Version**: 0.1.0 (Experimental)  
**Status**: ⚠️ Pre-release - Not ready for production

---

## Overview

AshJido bridges Ash Framework resources with Jido agents, automatically generating `Jido.Action` modules from Ash actions. The core functionality works, but the package requires additional polish before public release.

---

## Current State

### ✅ Working

| Component | Status | Notes |
|-----------|--------|-------|
| Core DSL (`jido do ... end`) | ✅ Working | Spark-based extension |
| Generator | ✅ Working | Generates Jido.Action modules at compile time |
| TypeMapper | ✅ Working | Maps Ash types to NimbleOptions schemas |
| Mapper | ⚠️ Partial | Works but error handling needs refactoring |
| Transformers | ✅ Working | Proper Spark transformer integration |
| `all_actions` DSL | ✅ Working | Bulk action exposure |
| Tests | ✅ Passing | 82/82 tests pass |

### ❌ Missing / Gaps

| Category | Gap | Priority |
|----------|-----|----------|
| **Error Handling** | Uses `%Jido.Error{}` struct instead of Splode-based errors | **P0** |
| **Dependencies** | ash 3.5.34 → 3.12.0 outdated | P1 |
| **Dependencies** | igniter 0.6.27 → 0.7.0 outdated | P1 |
| **Dependencies** | Missing: credo, dialyxir, ex_doc, excoveralls, git_hooks, git_ops, splode, zoi | P1 |
| **mix.exs** | Missing: `quality` alias, test coverage, dialyzer config, docs, package metadata | P1 |
| **Files** | Missing: `.github/workflows/ci.yml`, `.github/workflows/release.yml` | P2 |
| **Files** | Missing: `config/` directory (config.exs, dev.exs, test.exs) | P2 |
| **Files** | Missing: `.credo.exs` | P1 |
| **Files** | Missing: `CHANGELOG.md` | P1 |
| **Files** | Missing: `CONTRIBUTING.md` | P2 |
| **Files** | Missing: `LICENSE` file | P1 |
| **Files** | Missing: `guides/` directory | P2 |
| **Validation** | Not using Zoi for DSL config validation | P2 |

---

## Error Handling Gap (P0 - Critical)

### Current State

`AshJido.Mapper` uses ad-hoc `%Jido.Error{}` struct:

```elixir
# Current (problematic)
%Jido.Error{
  type: jido_type,
  message: Exception.message(ash_error),
  details: %{...}
}
```

### Required State

Should use `Jido.Action.Error` Splode-based errors:

```elixir
# Required
Jido.Action.Error.validation_error(message, %{ash_error: error, fields: fields})
Jido.Action.Error.execution_error(message, %{ash_error: error, reason: :forbidden})
Jido.Action.Error.internal_error(message, %{ash_error: error})
```

### Recommended Approach

1. **Do NOT** create a separate `AshJido.Error` Splode root
2. **Reuse** `Jido.Action.Error` as the canonical error module
3. **Optional**: Create thin `AshJido.Error` facade that delegates to `Jido.Action.Error`:

```elixir
defmodule AshJido.Error do
  alias Jido.Action.Error, as: ActionError

  def from_ash(%Ash.Error.Invalid{} = e), do: ActionError.validation_error("Invalid Ash request", %{ash_error: e})
  def from_ash(%Ash.Error.Forbidden{} = e), do: ActionError.execution_error("Forbidden", %{ash_error: e, reason: :forbidden})
  def from_ash(%Ash.Error.Framework{} = e), do: ActionError.internal_error("Ash framework error", %{ash_error: e})
  def from_ash(%Ash.Error.Unknown{} = e), do: ActionError.internal_error("Unknown Ash error", %{ash_error: e})
  def from_ash(other), do: ActionError.execution_error("Unhandled Ash error", %{ash_error: other})
end
```

---

## Dependencies Status

| Dependency | Current | Latest | Action |
|------------|---------|--------|--------|
| ash | 3.5.34 | 3.12.0 | ⚠️ Major upgrade needed |
| igniter | 0.6.27 | 0.7.0 | Minor upgrade |
| jido | 1.2.0 | 1.2.0 | ✅ Up-to-date |
| usage_rules | 0.1.23 | 0.1.26 | Dev only, minor |

### Missing Standard Dependencies

```elixir
# Required per GENERIC_PACKAGE_QA.md
{:credo, "~> 1.7", only: [:dev, :test], runtime: false},
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
{:ex_doc, "~> 0.31", only: :dev, runtime: false},
{:excoveralls, "~> 0.18", only: [:dev, :test]},
{:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
{:git_ops, "~> 2.9", only: :dev, runtime: false},
{:splode, "~> 0.2"},  # For error handling
{:zoi, "~> 0.14"},     # For schema validation
```

---

## mix.exs Gaps

### Missing Configuration

```elixir
# Required additions to mix.exs project/0:
aliases: aliases(),
cli: cli(),
name: "AshJido",
package: package(),
docs: docs(),
test_coverage: [tool: ExCoveralls, summary: [threshold: 90]],
dialyzer: [plt_local_path: "priv/plts/project.plt", plt_core_path: "priv/plts/core.plt"]

# Required alias:
quality: ["format --check-formatted", "compile --warnings-as-errors", "credo --min-priority higher", "dialyzer"]
```

---

## Action Plan

### Phase 1: Error Handling (P0) - Est. 3-8 hours

1. [ ] Add `splode` and `zoi` to dependencies
2. [ ] Create `AshJido.Error` facade module
3. [ ] Refactor `AshJido.Mapper.convert_ash_error_to_jido_error/1` to use Splode
4. [ ] Update Generator rescue clauses to use new error handling
5. [ ] Update tests to verify Splode error types
6. [ ] Verify 82 tests still pass

### Phase 2: Package Structure (P1) - Est. 3-5 hours

1. [ ] Update mix.exs with full configuration
2. [ ] Add standard dev/test dependencies
3. [ ] Upgrade ash to ~> 3.12 (test carefully)
4. [ ] Upgrade igniter to ~> 0.7
5. [ ] Add `.credo.exs`
6. [ ] Add `config/` directory structure
7. [ ] Add `CHANGELOG.md`
8. [ ] Add `LICENSE` (Apache-2.0)
9. [ ] Verify `mix quality` passes

### Phase 3: CI & Docs (P2) - Est. 1-2 days

1. [ ] Add `.github/workflows/ci.yml`
2. [ ] Add `.github/workflows/release.yml`
3. [ ] Add `CONTRIBUTING.md`
4. [ ] Add `guides/getting-started.md`
5. [ ] Set up ExCoveralls and verify coverage threshold
6. [ ] Generate and review HexDocs

---

## Risks

| Risk | Mitigation |
|------|------------|
| Ash 3.5 → 3.12 upgrade may break things | Dedicated PR, run all tests, add integration test |
| Error type change is breaking | Bump to 0.2.0, document in CHANGELOG |
| 90% coverage may be hard initially | Start with 70%, ratchet up |

---

## Files Checklist (GENERIC_PACKAGE_QA.md)

```
ash_jido/
├── .github/
│   └── workflows/
│       ├── ci.yml              ❌ MISSING
│       └── release.yml         ❌ MISSING
├── config/
│   ├── config.exs              ❌ MISSING
│   ├── dev.exs                 ❌ MISSING
│   └── test.exs                ❌ MISSING
├── guides/                     ❌ MISSING
│   └── getting-started.md      ❌ MISSING
├── lib/
│   └── ash_jido.ex             ✅ EXISTS
├── test/
│   ├── support/                ✅ EXISTS
│   └── ash_jido_test.exs       ✅ EXISTS
├── .credo.exs                  ❌ MISSING
├── .formatter.exs              ✅ EXISTS
├── .gitignore                  ✅ EXISTS
├── AGENTS.md                   ✅ EXISTS
├── CHANGELOG.md                ❌ MISSING
├── CONTRIBUTING.md             ❌ MISSING
├── LICENSE                     ❌ MISSING
├── mix.exs                     ⚠️ INCOMPLETE
├── mix.lock                    ✅ EXISTS
├── README.md                   ✅ EXISTS
└── usage-rules.md              ✅ EXISTS
```

---

## Summary

AshJido core functionality is solid (82 tests passing), but the package needs:

1. **P0**: Refactor error handling to use Splode via `Jido.Action.Error`
2. **P1**: Complete mix.exs, add dependencies, add required files
3. **P2**: Add CI/CD, guides, and polish

Estimated total effort: **1-2 weeks** for full GENERIC_PACKAGE_QA.md compliance.
