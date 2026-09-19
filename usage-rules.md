# AshJido usage rules

## Purpose

AshJido version 3 compiles selected Ash domain code interfaces and resource actions into native Jido v3 Actions.

Use AshJido when an Ash API must run in Jido Exec, Jido Flow, or a Jido Agent.

## Required design rules

- Prefer an Ash domain code interface and `jido do expose :interface end`.
- Use a resource `action :name` only as an explicit fallback.
- Expose each API. Do not generate all resource actions.
- Keep the Ash domain fixed at compile time.
- Run generated modules with `Jido.Exec.run/3` or as native Jido Flow steps.
- Put Ash run-time options under `context.ash`.
- Never pass `authorize?: false` from a Jido caller.
- Treat the stable `%{result:, page:, metadata:}` map as the Action output.
- Use `AshJido.Info.action_modules/1` for a generated Action catalog.

## Domain example

```elixir
defmodule MyApp.Accounts do
  use Ash.Domain, extensions: [AshJido]

  resources do
    resource MyApp.User do
      define :register_user, action: :register
      define :get_user, action: :read, get_by: [:id]
    end
  end

  jido do
    expose :register_user
    expose :get_user
  end
end
```

## Execution example

```elixir
Jido.Exec.run(
  MyApp.Accounts.Jido.GetUser,
  %{id: id},
  %{ash: %{actor: actor, tenant: tenant}}
)
```

Allowed `context.ash` keys are `actor`, `tenant`, `scope`, `tracer`, `context`, `timeout`, and `authorize?: true`.

Do not pass `domain`. Do not pass `authorize?: false`.

## Input rules

- Generated schemas are static Zoi schemas.
- Public Ash inputs are included by default.
- Use `action_parameters` for an explicit input allowlist.
- Use `private_inputs` for each intended private input.
- Use `schema_overrides` for an unsupported or application-specific Ash type.
- Do not convert user strings to atoms.

Read query features are opt-in:

```elixir
expose :list_users,
  filters: [:status],
  sorts: [:name],
  loads: [:profile],
  pagination: [type: :offset, max_page_size: 100]
```

Never add unrestricted filters, sorts, or run-time loads.

## Output rules

All successful generated Actions return:

```elixir
%{result: result, page: page_or_nil, metadata: metadata_or_nil}
```

AshJido serializes Ash records to maps. It includes public, non-sensitive, loaded fields only. Do not depend on Ash resource structs in Jido state or Flow results.

## Flow rules

- Use native `Jido.Flow`.
- Read generated Action values through the result envelope.
- Treat each Ash Action step as a separate transaction boundary.
- Put work that needs one database transaction in one Ash action.
- Add explicit compensation when earlier steps must be reversed.
- Do not add an AshJido Flow wrapper.

## Persistence rules

Define a user-owned resource with:

```elixir
jido do
  persistence_store()
end
```

Configure Jido with `{AshJido.Persistence.Adapter, resource: MyApp.JidoStore}`.

- The production data layer must support atomic query updates.
- Do not implement compare-and-swap as a read followed by a write.
- Treat `:conflict` as a stale writer.
- Treat an indeterminate write as unknown and restore before retrying.
- Do not store business records in the persistence byte store.

## Signal rules

- Add `AshJido.Notifier` to the Ash resource.
- Use an explicit signal type for every `publish` declaration.
- Select a small public payload.
- Sensitive and private fields must not enter signal data.
- Structured Ash metadata is at `signal.data[:ash_jido]`.
- Use a durable application outbox when delivery must be transactional.
- Do not emit a second signal from a generated Action.

## AI package boundaries

Use AshAi for direct LLM access to Ash actions, MCP, ReqLLM tools, and vectorization.

Use AshJido with Jido AI when an Ash action must participate in Jido Agents or Jido Flows.

- Do not make AshJido depend on `ash_ai`, `jido_ai`, or `req_llm`.
- Do not copy internal AshAi tool builders or serializers.
- Reuse public Ash DSL terms where they have the same meaning.
- Convert generated Actions with the public Jido AI tool adapter when needed.
