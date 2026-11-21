# Use an Ash row as Agent state

Bind one durable Jido Agent to an existing Ash resource row. AshJido infers
the Agent schema from the selected fields. An AgentServer Turn writes changes
through an Ash action and saves the Jido checkpoint in the same transaction.

## Configure the resource

This example adds a version attribute to a case. Each action that can change
projected fields must advance that version.

```elixir
attributes do
  uuid_primary_key :id
  attribute :status, :atom, constraints: [one_of: [:open, :closed]], allow_nil?: false
  attribute :priority, :integer, constraints: [min: 1, max: 5], allow_nil?: false
  attribute :version, :integer, default: 1, allow_nil?: false
end

actions do
  defaults [:read, create: [:status, :priority]]

  update :commit_agent_state do
    accept [:status, :priority]
    require_atomic? false
    change optimistic_lock(:version)
  end
end
```

The filtered form shown here works with AshSQLite and AshPostgres. It
checks the version and advances it in the update. External writers must
also use versioned writes. If using SQLite, enable
`write_transactions?/0` on your AshSQLite repo.

Set up a private [Ash persistence resource](persistence.md) in the same
database repo as the case. Configure one Jido instance with that store and a
stable namespace.

```elixir
{Jido,
 name: MyApp.Jido,
 namespace: "support",
 persistence: {AshJido.Persistence.Adapter, resource: MyApp.JidoStore}}
```

## Declare and start the Agent

```elixir
defmodule MyApp.Support.CaseAgent do
  use Jido.Agent, name: "support_case"
  import AshJido.State.DSL, only: [ash: 2]

  state do
    ash MyApp.Support.Case,
      fields: [:status, :priority],
      id: :primary_key,
      read: :read,
      update: :commit_agent_state,
      version: :version
  end

  routes do
    signal_source "/support/case"
    route "case.reprioritize", MyApp.Support.Reprioritize, as: :reprioritize
  end
end

{:ok, server} =
  AshJido.start_agent(MyApp.Jido, MyApp.Support.CaseAgent, case_id)

signal = MyApp.Support.CaseAgent.reprioritize_signal!(%{priority: 4})
{:ok, %{status: :committed}} = Jido.AgentServer.call(server, signal)
```

The direct call uses the same startup path as this form:

```elixir
Jido.start_agent(MyApp.Jido, MyApp.Support.CaseAgent,
  state: AshJido.row(case_id),
  partition: "support"
)
```

AshJido derives the Agent ID. Omit `:id` in both forms. If the Agent
requires a row and you omit it, the error points to `AshJido.row/2`.
An invalid key error lists the primary key fields.

The route's default state mapping takes the complete next state from the
Action output. For example, return `{:ok, %{context.agent_state | priority: priority}}`.
The named Ash action then validates the change and may normalize it. On success, the
Agent snapshot and Ash row contain the canonical values. The checkpoint
also keeps Jido's private runtime state, including Plugin state. An Action
output and any Reply, Signal, or Handoff payload built during evaluation keep
their original values. Use the snapshot or the Ash read action to read the
saved values.

Use a scalar primary key for a single key or a map for a composite key.
Pass the same `:tenant` for an attribute-multitenant resource on each call
that constructs the address. Use the tenant attribute's string value as the
tenant identifier. Pass it to `AshJido.row/2` or to `AshJido.start_agent/4`.
Agent IDs encode the primary key and tenant, so use
identifiers that can appear in logs and telemetry. Use `AshJido.State.address/4` with
`Jido.activate_agent/3` to restore an existing binding. A second address
cannot take ownership of the same scoped row in the same checkpoint store.
Keep a single private checkpoint store for each set of resources that share
the binding.

## Choose the projection

| Option | Behavior |
| --- | --- |
| `fields:` | Writable attributes accepted by the named update action. Only changed fields go to Ash. |
| `read_only:` | Project keys, generated values, calculations, aggregates, or related values. The version is always read-only. |
| `load:` | Pass an explicit Ash load for calculated, aggregate, or relationship values. |
| `codecs:` | Map a field to a trusted module with `encode/1` and `decode/1`. Return `{:ok, value}` or `{:error, reason}`. Use a codec to expose selected fields of an embedded or related record. |
| `arguments:` | Map a named update action argument to a writable state field. The argument gets that field's value when a state change calls the action. |
| `actor:` | Set a trusted `{module, function, args}` callback. The first argument is a map with `:address`, `:key`, and `:tenant`. Return `{:ok, actor}` or an error. |

State values keep native Ash types where they can be stored safely, such as
`Decimal`, atoms, dates, and nested values. Ash checks casts and constraints.
Required fields that Ash forbids or leaves unloaded fail the operation. An
allowed null remains `nil`. Prefer the default Jido Term codec for native
Elixir values. Select only values that are safe to put in Agent state and
the private checkpoint.

## Operate the binding

A stale row fails the Turn with `:ash_state_stale_row`. The next fresh Turn
reads the current row. An in-flight durable continuation keeps its original row
version and cannot commit over an external change. A checkpoint conflict
rolls back the Ash update and uses Jido's reconciliation path. If a caller
needs the exact result after a lost reply, submit a stable Turn ID with
`result_handoff: true` and use `Jido.turn_result/3`.

Jido sends Directives and AshJido releases action notifications after the
database commits. Use an application outbox or idempotent receiver when a
delivery must survive a crash between commit and dispatch. Stage writes to the
bound row through state and the configured commit action. An Action that
calls Ash directly during evaluation has its own transaction and delivery
guarantees. AshJido rejects a generated update or destroy Action when it
resolves to the executing Agent's bound row.

Jido stop or passivation keeps the binding. Jido deletion writes its
tombstone and preserves the Ash row. Create and destroy business rows through
your authorized Ash lifecycle APIs. A tombstoned address cannot start a
second lifetime.

Use one database repo for the update, checkpoint, and all related writes in
the commit action. List resources that custom changes write in the Ash
action's `touches_resources` option. Keep repo selection fixed. Custom
queries and changes must use the configured repo, and their hooks must leave
external effects for after the Agent Turn commits. If a projected calculation or relationship
depends on another row, make its writers advance the bound row's version to
detect concurrent changes. SQLite and PostgreSQL are supported. Context-per-tenant
databases and separate read or write repos cannot take part in this feature.

## Run the integration tests

`mix test` runs the SQLite tests with a temporary database file. To also
run the PostgreSQL tests, set `ASH_JIDO_POSTGRES_PORT` to the port of a test
server. The tests use `localhost` with the `postgres` user by default. They
create and remove a separate database for each test.
