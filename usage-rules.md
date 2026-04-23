# AshJido Usage Rules

## Core Integration Patterns

### Resource Extension Setup

- Add `extensions: [AshJido]` to Ash resources that should generate Jido actions.
- Put the `jido` section near the resource `actions` section so the exposed tool
  surface is easy to audit.
- Prefer explicit `action :name` entries for hand-curated tool catalogs.
- Use `all_actions` when the resource's public Ash action surface is already the
  intended tool surface.

### Individual Action Configuration

```elixir
jido do
  action :create
  action :read, name: "list_users", description: "List users"
  action :update, tags: ["user-management", "data-modification"]
end
```

### Bulk Action Exposure

```elixir
jido do
  all_actions
  all_actions except: [:internal_action, :admin_only]
  all_actions only: [:create, :read, :update]
end
```

- `all_actions` expands only Ash actions with `public?: true` by default.
- Generated schemas include only public accepted attributes and public action
  arguments by default.
- Use explicit `action :private_action` entries for deliberate private-action
  exposure.
- Use `include_private?: true` only for trusted/internal catalogs that may expose
  private Ash actions or private inputs.
- Ash authorization, policies, data-layer constraints, and runtime validation
  remain authoritative when generated actions execute.

## Naming and Modules

### Default Action Names

- `:create` actions default to `"create_<resource>"`.
- `:read` action `:read` defaults to `"list_<resources>"`.
- `:read` action `:by_id` defaults to `"get_<resource>_by_id"`.
- Other read actions default to `"<resource>_<action_name>"`.
- `:update` actions default to `"update_<resource>"`.
- `:destroy` actions default to `"delete_<resource>"`.
- Custom actions default to `"<resource>_<action_name>"`, except common verbs
  like `:activate` and `:archive`, which become `"<verb>_<resource>"`.

### Module Generation

- Default modules are generated under the resource namespace, for example
  `MyApp.Accounts.User.Jido.Create`.
- `name:` changes the Jido action name used for discovery and tool payloads.
- `module_name:` changes the generated Elixir module.
- If the same Ash action is exposed more than once, give each entry an explicit
  `module_name:` so modules do not collide.

## Context Requirements

AshJido resolves the Ash domain in this order:

1. `context[:domain]`
2. the resource's static `domain:` configuration
3. `ArgumentError` if neither is available

```elixir
context = %{
  domain: MyApp.Accounts,
  actor: current_user,
  tenant: "org_123",
  authorize?: true,
  scope: MyApp.Scope.for(current_user),
  context: %{request_id: "req_123"},
  timeout: 15_000
}
```

- Pass `actor:` for policy-aware authorization.
- Pass `tenant:` for multi-tenant resources.
- Pass `scope:` when using Ash scopes.
- Pass `context:` for Ash action context metadata.
- Pass `signal_dispatch:` to override generated-action signal dispatch at
  runtime.

## Query Parameters

Generated read actions accept optional query parameters by default:

```elixir
MyApp.Blog.Post.Jido.Read.run(
  %{
    filter: %{status: %{in: ["draft", "published"]}},
    sort: [%{"field" => "inserted_at", "direction" => "desc"}],
    limit: 20,
    offset: 40
  },
  %{domain: MyApp.Blog}
)
```

- `filter` uses Ash `filter_input` syntax.
- `sort` supports JSON-style maps, keyword lists, or strings like
  `"-inserted_at,title"`.
- `limit` and `offset` support pagination.
- `load` is available only when the action configures `allowed_loads`.
- Query params use Ash's safe public input parsing and honor policies.
- Disable query params with `query_params?: false`.
- Allow runtime relationship loads with `allowed_loads` or
  `read_allowed_loads`.
- Bound result sizes with `max_page_size` or `read_max_page_size`.

## Signals and Telemetry

### Resource Publications

Use `AshJido.Notifier` with `publish` or `publish_all` for Ash-native lifecycle
publications to a Jido signal bus:

```elixir
defmodule MyApp.Blog.Post do
  use Ash.Resource,
    domain: MyApp.Blog,
    extensions: [AshJido],
    notifiers: [AshJido.Notifier]

  jido do
    signal_bus MyApp.SignalBus
    signal_prefix "blog"

    publish :create, "blog.post.created", include: [:id, :title]
    publish_all :update, include: :changes_only
  end
end
```

`publish` supports `include: :pkey_only | :all | :changes_only | [:field]`,
`metadata: [:actor, :tenant, :changes, :previous_state]`, and `condition: fun`.

### Generated-Action Signals

Use `emit_signals?: true` when signal dispatch should be tied to generated
action execution:

```elixir
jido do
  action :create,
    emit_signals?: true,
    signal_dispatch: {:pid, target: self()},
    telemetry?: true
end
```

- Generated-action signals require `signal_dispatch` from the DSL or context.
- Both generated-action signals and notifier publications use
  `AshJido.SignalFactory`.
- Default signal types are `{prefix}.{resource}.{action}`.
- Default signal sources are `/ash/{resource}/{action_type}/{action}`.
- Default subjects are `/{resource}/{primary_key}` when a primary key exists.
- Generated-action signals put primary key data in `signal.data` by default;
  use `signal_include` to widen the payload intentionally.
- Notifier publications use the configured `include` mode for `signal.data`.
- Ash metadata lives in `signal.extensions["jido_metadata"]`.

### Telemetry

Telemetry is opt-in with `telemetry?: true` and emits:

- `[:jido, :action, :ash_jido, :start]`
- `[:jido, :action, :ash_jido, :stop]`
- `[:jido, :action, :ash_jido, :exception]`

Telemetry metadata includes resource/action/module identity, domain and tenant
presence, actor presence, read-load/query configuration, signal enablement, and
signal delivery counters.

## Tools and Sensor Bridge

- Use `AshJido.Tools.actions/1` to list generated action modules for a resource
  or domain.
- Use `AshJido.Tools.tools/1` to export name/description/schema/function maps
  for generic agent and LLM integrations.
- Use `AshJido.SensorDispatchBridge.forward/2`, `forward_many/2`, or
  `forward_or_ignore/2` to feed dispatched `Jido.Signal` messages into
  `Jido.Sensor.Runtime`.

## Output and Mutation Semantics

- `output_map?: true` is the default and converts Ash structs to public-field maps.
- Set `output_map?: false` to preserve Ash structs.
- Read actions return lists.
- Create and update actions return the resulting record.
- Update and destroy actions require the resource primary key fields in params.
- Resources with the default `[:id]` primary key still use `id`.
- Destroy actions also pass through declared Ash destroy action arguments.
- Custom Ash actions use `Ash.run_action!`; non-map results are wrapped for
  Jido output validation.

## Error Handling

Ash errors are converted to `Jido.Action.Error` exceptions:

- `Ash.Error.Invalid` becomes `Jido.Action.Error.InvalidInputError`.
- `Ash.Error.Forbidden` becomes `Jido.Action.Error.ExecutionFailureError` with
  `details.reason == :forbidden`.
- `Ash.Error.Framework` becomes `Jido.Action.Error.InternalError`.
- `Ash.Error.Unknown` becomes `Jido.Action.Error.InternalError`.
- Other exceptions become `Jido.Action.Error.ExecutionFailureError`.

Field-level validation errors are preserved in `error.details.fields`, and the
original Ash error is preserved in `error.details.ash_error`.

## Best Practices

### Security

- Prefer Ash `public?: true` boundaries for generated tool catalogs.
- Use `include_private?: true` only for trusted/internal tools.
- Keep Ash policies as the authorization source of truth.
- Use `except:` or explicit action entries to avoid exposing destructive or
  administrative actions unintentionally.
- Bound large read actions with `max_page_size`.

### AI Integration

- Use clear verb-first `name:` values for agent-facing tools.
- Add concise `description:` text and focused `tags:`.
- Use `category:` for routing; `all_actions` defaults to `"ash.<action_type>"`
  when no category override is provided.
- Export tool payloads through `AshJido.Tools.tools/1` for generic integrations.
- For `Jido.AI.Agent`, configure generated action modules directly in `tools:`.

### Documentation

- Generated modules include docs pointing back to the Ash resource/action.
- Keep README, guides, changelog, and these usage rules in sync when changing
  DSL options, runtime behavior, or generated schemas.
- Do not edit `CHANGELOG.md` directly in normal PRs; the release workflow
  generates it from conventional commits through `git_ops`.
- Run `mix docs` and `mix doctor --raise` after public documentation changes.

## Troubleshooting

### Domain Not Provided

- AshJido uses `context[:domain]` first, then the resource's static `domain:`.
- Provide `%{domain: MyApp.Domain}` when overriding or when the resource has no
  static domain.
- Ensure the resource is registered in the provided domain.

### Action Not Found

- Verify the action exists in the resource `actions` section.
- Check spelling and exact action name.
- For `all_actions`, ensure the action is public or opt in with
  `include_private?: true`.

### Query Parameter Errors

- Confirm the target is a read action and `query_params?` is enabled.
- Use public Ash attributes for `filter` and `sort`.
- Use `max_page_size` to make pagination bounds explicit.

### Signal Dispatch Errors

- `emit_signals?: true` requires `signal_dispatch` in the DSL or context.
- Use `AshJido.Notifier` and `signal_bus` for resource-level Jido bus
  publications.
- Use `signal_type` and `signal_source` only when the default envelope should be
  overridden.

### Module Compilation Issues

- Ensure `jido`, `jido_action`, and `jido_signal` dependencies are available.
- Give duplicate generated entries explicit `module_name:` values.
- Check for circular resource/module references.
