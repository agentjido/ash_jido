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
  domain: MyApp.Accounts,  # REQUIRED
  actor: current_user,     # optional: for authorization
  tenant: "org_123"        # optional: for multi-tenancy
}

MyApp.User.Jido.Create.run(params, context)
```

## DSL Options

### Individual Actions

```elixir
jido do
  action :create
  action :read, name: "list_users", description: "List all users"
  action :update, tags: ["user-management"]
  action :special, output_map?: false  # preserve Ash structs
end
```

### Bulk Exposure

```elixir
jido do
  all_actions
  all_actions except: [:destroy, :internal]
  all_actions only: [:create, :read]
  all_actions tags: ["public-api"]
end
```

### Action Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | string | auto-generated | Custom Jido action name |
| `module_name` | atom | `Resource.Jido.Action` | Custom module name |
| `description` | string | from Ash action | Action description |
| `tags` | list(string) | `[]` | Tags for categorization |
| `output_map?` | boolean | `true` | Convert structs to maps |

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

## Compatibility

- Elixir: ~> 1.18
- Ash: ~> 3.12
- Jido: ~> 1.1

## Documentation

- [Getting Started](guides/getting-started.md) — comprehensive usage
- [Interactive Demo](guides/ash-jido-demo.livemd) — try in Livebook
- [Usage Rules](usage-rules.md) — AI/LLM patterns

## License

MIT
