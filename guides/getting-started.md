# Getting started

AshJido version 3 treats the Ash domain API as the main boundary. It compiles selected code interfaces into normal Jido Actions.

## 1. Add Ash code interfaces

```elixir
defmodule MyApp.Accounts do
  use Ash.Domain, extensions: [AshJido]

  resources do
    resource MyApp.Accounts.User do
      define :register_user, action: :register
      define :get_user, action: :read, get_by: [:id]
      define :list_users, action: :read
      define_calculation :score_user,
        calculation: :score,
        args: [{:arg, :weight}, {:ref, :reputation}]
    end
  end

  jido do
    expose :register_user
    expose :get_user

    expose :list_users,
      filters: [:status],
      sorts: [:name, :inserted_at],
      loads: [:profile],
      pagination: [type: :both, max_page_size: 100]

    expose :score_user
  end
end
```

`expose` uses the public code interface name. AshJido reads the target resource, action, input transforms, `get_by`, default options, and calculation arguments at compile time.

The default module is `Domain.Jido.InterfaceName`. Set `name:` to change the Jido Action name. Set `module_name:` to change the Elixir module.

## 2. Inspect the result

```elixir
AshJido.Info.action_modules(MyApp.Accounts)
#=> [
#     MyApp.Accounts.Jido.RegisterUser,
#     MyApp.Accounts.Jido.GetUser,
#     MyApp.Accounts.Jido.ListUsers,
#     MyApp.Accounts.Jido.ScoreUser
#   ]

descriptor = MyApp.Accounts.Jido.GetUser.__ash_jido__()
descriptor.domain
#=> MyApp.Accounts
```

`AshJido.Info.descriptors/1` returns all normalized descriptors. Each descriptor has a deterministic ownership fingerprint.

## 3. Run through Jido

```elixir
context = %{
  ash: %{
    actor: current_user,
    tenant: "tenant-1",
    context: %{request_id: request_id},
    timeout: 15_000
  }
}

{:ok, %{result: user, page: nil, metadata: nil}} =
  Jido.Exec.run(
    MyApp.Accounts.Jido.RegisterUser,
    %{name: "Ada", email: "ada@example.com"},
    context
  )
```

Do not put Ash values at the root of the Jido context. Use the `:ash` namespace.

The domain is fixed in the generated Action. AshJido rejects a run-time domain and rejects `authorize?: false`. Ash remains responsible for policies and field policies.

## 4. Configure an exposure

These options are available on `expose` and direct `action` declarations:

| Option | Purpose |
| --- | --- |
| `name` | Jido Action name |
| `module_name` | Generated Elixir module |
| `description` | Action description |
| `identity` | Named Ash identity, explicit fields, or `false` |
| `action_parameters` | Explicit input allowlist |
| `private_inputs` | Explicit private inputs that the Action can accept |
| `select` | Static Ash select list |
| `load` | Static Ash load statement |
| `filters` | Run-time filter field allowlist |
| `sorts` | Run-time sort field allowlist |
| `loads` | Run-time load allowlist |
| `pagination` | Offset or keyset controls and maximum page size |
| `schema_overrides` | Zoi schemas for unsupported or special inputs |

Private inputs are never exposed by default. `private_inputs` must list each intended private input.

## 5. Use explicit read controls

Read controls do not exist unless the exposure enables them:

```elixir
{:ok, output} =
  Jido.Exec.run(
    MyApp.Accounts.Jido.ListUsers,
    %{
      filter: %{status: %{in: [:active, :pending]}},
      sort: [%{field: :name, direction: :asc}],
      load: [:profile],
      limit: 25,
      offset: 0,
      count: true
    },
    context
  )
```

AshJido validates field names against the configured allowlists. It then uses Ash input APIs for the query.

Paged reads use the same envelope. `result` contains the records and `page` contains normalized offset or keyset data.

## 6. Use a resource fallback when needed

```elixir
defmodule MyApp.Accounts.User do
  use Ash.Resource,
    domain: MyApp.Accounts,
    extensions: [AshJido]

  jido do
    action :register
    action :update_profile, identity: [:account_id, :external_id]
    action :archive, action_parameters: [:reason]
  end
end
```

The resource form requires a compile-time domain. It generates modules under `Resource.Jido`.

Use a domain declaration for a direct action when the resource cannot own the DSL:

```elixir
jido do
  action :archive_user, MyApp.Accounts.User, :archive
end
```

## 7. Understand the output and errors

Every success has this envelope:

```elixir
%{result: value, page: nil, metadata: nil}
```

Ash resources are serialized to maps. Only public, non-sensitive, loaded fields are present. Dates and decimals use stable external forms.

AshJido maps failures to a small Jido error surface:

- invalid input
- not found
- forbidden
- conflict
- timeout
- internal failure

The error details do not contain changesets, queries, exception structs, or sensitive input values.
