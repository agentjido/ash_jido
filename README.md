# AshJido

Bridge Ash Framework resources with Jido agents. Generates `Jido.Action` modules from Ash actions at compile time.

## What This Library Does

- Adds a `jido` DSL section to Ash resources
- Generates `Jido.Action` modules at compile time for selected actions
- Maps Ash argument types to NimbleOptions schemas
- Runs actions via Ash with provided `domain`, `actor`, and `tenant`
- Converts Ash errors to `Jido.Action.Error` (Splode-based) errors

## What It Does Not Do

- Auto-discover domains or resources (domain is explicit and required)
- Add pagination or query-layer magic
- Bypass Ash authorization, policies, or data layers

## Installation

```bash
mix igniter.install ash_jido
```

Or add manually to `mix.exs`:

```elixir
def deps do
  [
    {:ash_jido, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
defmodule MyApp.User do
  use Ash.Resource,
    domain: MyApp.Accounts,
    extensions: [AshJido]

  actions do
    create :register
    read :by_id
    update :profile
  end

  jido do
    action :register, name: "create_user"
    action :by_id, name: "get_user"
    action :profile
  end
end
```

Generated modules:

```elixir
{:ok, user} = MyApp.User.Jido.Register.run(
  %{name: "John", email: "john@example.com"},
  %{domain: MyApp.Accounts}
)
```

## Context Requirements

The `domain` is **required** in context. An `ArgumentError` is raised if missing.

```elixir
context = %{
  domain: MyApp.Accounts,       # REQUIRED
  actor: current_user,          # optional: for authorization
  tenant: "org_123",            # optional: for multi-tenancy
  authorize?: true,             # optional: explicit authorization mode
  tracer: [MyApp.Tracer],       # optional: Ash tracer modules
  scope: MyApp.Scope.for(user), # optional: Ash scope
  context: %{request_id: "1"},  # optional: Ash action context
  timeout: 15_000,              # optional: Ash operation timeout
  signal_dispatch: {:pid, target: self()} # optional: override signal dispatch
}

MyApp.User.Jido.Create.run(params, context)
```

## DSL Options

### Individual Actions

```elixir
jido do
  action :create
  action :read, name: "list_users", description: "List all users", load: [:profile]
  action :update, category: "ash.update", tags: ["user-management"], vsn: "1.0.0"
  action :special, output_map?: false  # preserve Ash structs
end
```

### Bulk Exposure

```elixir
jido do
  all_actions
  all_actions except: [:destroy, :internal]
  all_actions only: [:create, :read]
  all_actions category: "ash.resource"
  all_actions tags: ["public-api"]
  all_actions vsn: "1.0.0"
  all_actions only: [:read], read_load: [:profile]
end
```

### Action Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | string | auto-generated | Custom Jido action name |
| `module_name` | atom | `Resource.Jido.Action` | Custom module name |
| `description` | string | from Ash action | Action description |
| `category` | string | `nil` | Category for discovery/tool organization |
| `tags` | list(string) | `[]` | Tags for categorization |
| `vsn` | string | `nil` | Optional semantic version metadata |
| `output_map?` | boolean | `true` | Convert structs to maps |
| `load` | term | `nil` | Static `Ash.Query.load/2` for read actions |
| `emit_signals?` | boolean | `false` | Emit Jido signals from Ash notifications (create/update/destroy) |
| `signal_dispatch` | term | `nil` | Default signal dispatch config (can be overridden via context) |
| `signal_type` | string | derived | Override emitted signal type |
| `signal_source` | string | derived | Override emitted signal source |
| `telemetry?` | boolean | `false` | Emit Jido-namespaced telemetry for generated action execution |

### all_actions Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `only` | list(atom) | all actions | Limit generated actions |
| `except` | list(atom) | `[]` | Exclude actions |
| `category` | string | `ash.<action_type>` | Category added to generated actions |
| `tags` | list(string) | `[]` | Tags added to all generated actions |
| `vsn` | string | `nil` | Optional semantic version metadata for generated actions |
| `read_load` | term | `nil` | Static `Ash.Query.load/2` for generated read actions |
| `emit_signals?` | boolean | `false` | Emit Jido signals from generated create/update/destroy actions |
| `signal_dispatch` | term | `nil` | Default signal dispatch config for generated actions |
| `signal_type` | string | derived | Override emitted signal type |
| `signal_source` | string | derived | Override emitted signal source |
| `telemetry?` | boolean | `false` | Emit Jido-namespaced telemetry for generated action execution |

## Telemetry

Telemetry is opt-in per action (or via `all_actions`):

```elixir
jido do
  action :create, telemetry?: true
end
```

When enabled, generated actions emit:

- `[:jido, :action, :ash_jido, :start]`
- `[:jido, :action, :ash_jido, :stop]`
- `[:jido, :action, :ash_jido, :exception]`

Metadata includes resource/action/module identity, domain/tenant, actor presence, signaling/read-load flags, and signal delivery counters.

## Tool Export Helpers

Use `AshJido.Tools` to list generated actions and export LLM-friendly tool maps:

```elixir
# Generated action modules for a resource
AshJido.Tools.actions(MyApp.Accounts.User)

# Generated action modules for all resources in a domain
AshJido.Tools.actions(MyApp.Accounts)

# Tool payloads (name/description/schema/function) for agent/LLM integrations
AshJido.Tools.tools(MyApp.Accounts.User)
```

## Sensor Bridge

`AshJido.SensorDispatchBridge` keeps the dispatch-first signal model while adding optional sensor runtime forwarding:

```elixir
# Accepts %Jido.Signal{}, {:signal, %Jido.Signal{}}, and {:signal, {:ok, %Jido.Signal{}}}
:ok = AshJido.SensorDispatchBridge.forward(signal_message, sensor_runtime)

# Batch forwarding with per-message errors
%{forwarded: count, errors: errors} =
  AshJido.SensorDispatchBridge.forward_many(messages, sensor_runtime)

# Ignore non-signal mailbox noise safely
:ok | :ignored | {:error, :runtime_unavailable} =
  AshJido.SensorDispatchBridge.forward_or_ignore(message, sensor_runtime)
```

### Default Naming

| Action Type | Pattern | Example |
|-------------|---------|---------|
| `:create` | `create_<resource>` | `create_user` |
| `:read` (`:read`) | `list_<resources>` | `list_users` |
| `:read` (`:by_id`) | `get_<resource>_by_id` | `get_user_by_id` |
| `:update` | `update_<resource>` | `update_user` |
| `:destroy` | `delete_<resource>` | `delete_user` |

## Troubleshooting

**`AshJido: :domain must be provided in context`**
- Pass `%{domain: MyApp.Domain}` as the second argument to `run/2`

**`Update actions require an 'id' parameter`**
- Include `id` in params for `:update` and `:destroy` actions

**`Action X not found in resource`**
- Check `jido action :...` entries match defined Ash actions

For a full error contract and telemetry interpretation, see [Walkthrough: Failure Semantics](guides/walkthrough-failure-semantics.md).

## Compatibility

- Elixir: ~> 1.18
- Ash: ~> 3.12
- Jido: ~> 1.1

## Documentation

- [Getting Started](guides/getting-started.md) — comprehensive usage
- [Walkthrough: Policy, Scope, and Authorization](guides/walkthrough-policy-scope-auth.md) — policy-aware actor, scope, tenant patterns
- [Walkthrough: AshPostgres Consumer Harness](guides/walkthrough-ash-postgres-consumer.md) — real DB-backed integration scenarios
- [Walkthrough: Failure Semantics](guides/walkthrough-failure-semantics.md) — deterministic errors and telemetry outcomes
- [Walkthrough: Agent Tool Wiring](guides/walkthrough-agent-tool-wiring.md) — domain tool catalogs and safe execution wrappers
- [Walkthrough: Resource to Action](guides/walkthrough-resource-to-action.md) — define resources and run generated actions
- [Walkthrough: Signals, Telemetry, and Sensors](guides/walkthrough-signals-telemetry-sensors.md) — notification signals and observability
- [Walkthrough: Tools and AI Integration](guides/walkthrough-tools-and-ai.md) — action metadata and tool export
- [Interactive Demo](guides/ash-jido-demo.livemd) — try in Livebook
- [Usage Rules](usage-rules.md) — AI/LLM patterns

## Real Consumer Integration App

A full AshPostgres-backed consumer harness lives at `ash_jido_consumer/`.

It exercises real integration scenarios end-to-end:

- context passthrough + policy behavior
- relationship-aware reads (`load`)
- notifications to signals (`emit_signals?`)
- Jido telemetry emission (`telemetry?`)

## License

MIT
