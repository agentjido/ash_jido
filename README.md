# AshJido

[![Hex.pm](https://img.shields.io/hexpm/v/ash_jido.svg)](https://hex.pm/packages/ash_jido)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/ash_jido/)
[![CI](https://github.com/agentjido/ash_jido/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/ash_jido/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/ash_jido.svg)](https://github.com/agentjido/ash_jido/blob/main/LICENSE)

AshJido compiles selected Ash APIs into native Jido v3 Actions. It keeps Ash as the source of business rules, authorization, and data access. It uses Jido for execution, Flow orchestration, Agents, and persistence lifecycle.

## Main features

- Domain-first compilation from Ash code interfaces
- Resource action fallback for APIs that do not have code interfaces
- Static Zoi input and output schemas
- Native execution with `Jido.Exec`
- Native composition with `Jido.Flow`
- Fixed compile-time domains and namespaced Ash context
- Public, non-sensitive result serialization
- Explicit filter, sort, load, and pagination allowlists
- Ash-backed Jido persistence with atomic compare-and-swap
- Ash notifier publications to a Jido Signal bus

AshJido does not add a second Action, Flow, Agent, or Signal runtime.

## Installation

Add AshJido to `mix.exs`:

```elixir
def deps do
  [
    {:ash_jido, "~> 3.0.0-beta.1"}
  ]
end
```

Or use Igniter:

```bash
mix igniter.install ash_jido
```

Version 3 uses the Hex releases of `jido`, `jido_action`, and `jido_signal` version 3.

## Define the Ash API

Define normal Ash actions and public domain code interfaces:

```elixir
defmodule MyApp.Accounts.User do
  use Ash.Resource,
    domain: MyApp.Accounts,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :email, :string, allow_nil?: false, public?: true
    attribute :secret, :string, sensitive?: true
  end

  actions do
    defaults [:read]

    create :register do
      accept [:name, :email]
    end
  end
end

defmodule MyApp.Accounts do
  use Ash.Domain, extensions: [AshJido]

  resources do
    resource MyApp.Accounts.User do
      define :register_user, action: :register
      define :get_user, action: :read, get_by: [:id]
      define :list_users, action: :read
    end
  end

  jido do
    expose :register_user
    expose :get_user

    expose :list_users,
      filters: [:email],
      sorts: [:name],
      pagination: [type: :offset, max_page_size: 100]
  end
end
```

This creates these normal Jido Actions:

- `MyApp.Accounts.Jido.RegisterUser`
- `MyApp.Accounts.Jido.GetUser`
- `MyApp.Accounts.Jido.ListUsers`

## Run a generated Action

```elixir
{:ok, output} =
  Jido.Exec.run(
    MyApp.Accounts.Jido.RegisterUser,
    %{name: "Ada", email: "ada@example.com"},
    %{ash: %{actor: current_user, tenant: tenant}}
  )

%{
  result: %{id: id, name: "Ada", email: "ada@example.com"},
  page: nil,
  metadata: nil
} = output
```

The domain is part of the generated descriptor. Run-time context can contain these `context.ash` values:

- `actor`
- `tenant`
- `scope`
- `tracer`
- `context`
- `timeout`
- `authorize?: true`

A caller cannot supply a different domain or set `authorize?: false`.

## Stable contracts

Generated Actions use static Zoi schemas. Unsupported custom Ash types fail at compile time unless the exposure supplies a `schema_overrides` entry.

All successful calls return this shape:

```elixir
%{
  result: result,
  page: page_or_nil,
  metadata: metadata_or_nil
}
```

Ash resource structs become maps. The serializer includes public, non-sensitive fields only. It omits unloaded and forbidden fields.

## Resource fallback

Use the extension on a resource when a code interface is not available:

```elixir
defmodule MyApp.Accounts.User do
  use Ash.Resource,
    domain: MyApp.Accounts,
    extensions: [AshJido]

  jido do
    action :register
    action :update_profile, identity: :unique_email
  end
end
```

This form generates modules under `MyApp.Accounts.User.Jido`.

## Jido Flow

Generated modules are normal Jido Actions. Use them directly in `Jido.Flow`:

```elixir
alias Jido.Flow.Builder

{:ok, flow} =
  Builder.new(name: "register_and_fetch")
  |> Builder.step("register", MyApp.Accounts.Jido.RegisterUser, %{
    name: Builder.input(:name),
    email: Builder.input(:email)
  })
  |> Builder.step("fetch", MyApp.Accounts.Jido.GetUser, %{
    id: Builder.result("register", [:result, :id])
  })
  |> Builder.output(Builder.result("fetch"))
  |> Builder.build()

Jido.Exec.run(flow, %{name: "Ada", email: "ada@example.com"}, context)
```

AshJido does not provide a Flow wrapper. Flow steps keep separate Ash transaction boundaries. Design compensation in the Flow when a later step can fail.

## More guides

- [Getting started](guides/getting-started.md)
- [Jido Flow composition](guides/flow.md)
- [Ash persistence adapter](guides/persistence.md)
- [Jido Signal publications](guides/signals.md)
- [Migration from AshJido v1](guides/v3-migration.md)
- [Usage rules](usage-rules.md)
