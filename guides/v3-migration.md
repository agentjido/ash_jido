# Migrate to AshJido version 3

Version 3 is a new contract for Jido version 3. Review generated module names, inputs, outputs, context, and signal payloads before deployment.

## Dependency change

```elixir
{:ash_jido, "~> 3.0.0-beta.1"}
```

AshJido version 3 uses the Hex releases of `jido`, `jido_action`, `jido_signal`, and `zoi`. Remove local path or Git overrides after the application completes its Jido v3 migration.

## Prefer domain code interfaces

Old resource exposure:

```elixir
defmodule MyApp.User do
  use Ash.Resource, extensions: [AshJido]

  jido do
    action :register
    action :read, name: "list_users"
  end
end
```

New domain exposure:

```elixir
defmodule MyApp.Accounts do
  use Ash.Domain, extensions: [AshJido]

  resources do
    resource MyApp.User do
      define :register_user, action: :register
      define :list_users, action: :read
    end
  end

  jido do
    expose :register_user
    expose :list_users
  end
end
```

The new default modules are `MyApp.Accounts.Jido.RegisterUser` and `MyApp.Accounts.Jido.ListUsers`.

Resource `action` declarations remain as an explicit fallback. `all_actions` is removed. Expose each intended API.

## Run through Jido Exec

Old direct call:

```elixir
MyApp.User.Jido.Register.run(params, %{domain: MyApp.Accounts, actor: actor})
```

New call:

```elixir
Jido.Exec.run(
  MyApp.Accounts.Jido.RegisterUser,
  params,
  %{ash: %{actor: actor}}
)
```

The domain is fixed at compile time. Remove all run-time domain overrides. Put Ash context under `context.ash`. A caller cannot set `authorize?: false`.

## Update result handling

Version 3 always returns a stable envelope:

```elixir
%{result: value, page: page_or_nil, metadata: metadata_or_nil}
```

Remove `output_map?`. Resource results are always safe maps. Only public, non-sensitive, loaded fields are present.

Update Flow result paths. For example, a created record ID is at `[:result, :id]`.

## Replace broad query options

Remove `query_params?`, `allowed_loads`, and implicit read controls. Add explicit allowlists:

```elixir
expose :list_users,
  filters: [:status, :email],
  sorts: [:name, :inserted_at],
  loads: [:profile],
  pagination: [type: :offset, max_page_size: 100]
```

Sort input is now a list of `%{field: field, direction: direction}` entries. Pagination data is returned in the envelope.

## Replace private exposure

Remove `include_private?`. Inputs follow the Ash public boundary. Use `private_inputs: [...]` only for specific trusted inputs. Sensitive output fields remain excluded.

Use `action_parameters: [...]` when a generated Action must expose only part of the Ash input surface.

## Replace generated Action catalogs

`AshJido.Tools` is removed. Use:

```elixir
AshJido.Info.action_modules(MyApp.Accounts)
AshJido.Info.descriptors(MyApp.Accounts)
```

Use Jido AI adapters when an application must convert Actions to model tools. AshJido does not depend on `ash_ai`, `jido_ai`, or `req_llm`.

## Update custom types

Generated Action schemas are static Zoi schemas. Common Ash scalar, enum, new type, union, array, typed map, struct, and embedded resource types are mapped at compile time.

An unsupported type now fails compilation. Add a schema override:

```elixir
expose :search,
  schema_overrides: %{query: Zoi.string() |> Zoi.min(1)}
```

## Update identity handling

Update and destroy Actions require an identity. The default is the primary key. Use a named or composite identity when needed:

```elixir
action :update_profile, identity: :unique_email
action :remove_membership, identity: [:account_id, :user_id]
```

AshJido performs the authorized record read through Ash before the update or destroy.

## Update signals

Remove generated-Action signal options and `publish_all`. Add `AshJido.Notifier` and explicit publications:

```elixir
use Ash.Resource,
  extensions: [AshJido],
  notifiers: [AshJido.Notifier]

jido do
  signal_bus MyApp.SignalBus
  publish :create, "accounts.user.created", include: [:id, :email]
end
```

Signal types are required. There is no derived prefix. Optional structured metadata is at `signal.data[:ash_jido]`.

## Error changes

Do not match Ash exception structs in Jido callers. Match the Jido Action error class and the safe `details.reason` value. Version 3 does not expose Ash changesets, queries, raw exceptions, or input values in error details.

## Removed API summary

| Removed version 1 API | Version 3 replacement |
| --- | --- |
| `all_actions` | Explicit `expose` or `action` entries |
| Run-time `domain` | Compile-time domain descriptor |
| Root Ash context keys | `context.ash` |
| `output_map?` | Stable serialized envelope |
| `include_private?` | `private_inputs` allowlist |
| `query_params?` | Explicit read allowlists |
| `AshJido.Tools` | `AshJido.Info` |
| Direct Action signals | `AshJido.Notifier` |
| Sensor dispatch bridge | Native Jido Signal bus and sensors |
| AshJido telemetry wrapper | Native Jido and Ash telemetry |
