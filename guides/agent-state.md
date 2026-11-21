# Use an Ash row as Agent state

Bind one durable Jido Agent to an existing Ash resource row. The
`AshJido.State` Plugin supplies the Agent's domain schema from the selected
fields. Jido saves the row changes, checkpoint, and Turn receipt in one
transaction through the AshJido persistence adapter.

## Configure the resource

This example adds a version and a row generation to a case. Each action
that can change projected fields must advance the version. Each insert must
generate a fresh generation UUID. The provider uses it to distinguish a
replacement row with the same primary key and version. If the table already
has rows, backfill a distinct generation for each row before using the Agent.

```elixir
attributes do
  uuid_primary_key :id
  attribute :status, :atom, constraints: [one_of: [:open, :closed]], allow_nil?: false
  attribute :priority, :integer, constraints: [min: 1, max: 5], allow_nil?: false
  attribute :row_generation, :uuid, allow_nil?: false, writable?: false, default: &Ash.UUID.generate/0
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
  use Jido.Agent, name: "support_case", plugins: [AshJido.State]

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
An invalid key error lists the primary key fields. If the readiness wait
elapses, the error includes the pending Agent address. Check the activation at
that address before retrying.

The route's default state mapping takes the complete next state from the
Action output. For example, return `{:ok, %{context.agent_state | priority: priority}}`.
The named Ash action validates the change. Each writable field must round
trip with the exact value the Turn proposed. If Ash changes a writable
value, the Turn fails with `{:ash_state_writable_field_changed, field}` and
the transaction rolls back. Canonicalize writable values before returning
them from the Turn. Ash can still update derived read-only fields and the
row version. Use the Agent snapshot or the Ash read action to read those
saved values. The checkpoint also keeps Jido's private runtime state,
including additive Plugin state. Jido rejects a state projection that
contains a field outside the schema declared by the Ash state source.

Use a scalar primary key for a single key or a map for a composite key.
Supported keys use built-in UUID, string, binary, integer, atom, or boolean
types. The read action must supply defaults for its required arguments.
Pass the Ash tenant token as a string to `AshJido.row/2` or
`AshJido.start_agent/4`. AshJido uses the resource's `parse_attribute` and
`tenant_from_attribute` callbacks to resolve tenant aliases to one address.
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
| `read_only:` | Project keys, generated values, calculations, aggregates, or related values. The version and generation are always read-only. |
| `generation:` | Name the row generation UUID attribute. The default name is `:row_generation`. |
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
reads the current row. If the row was replaced, `:ash_state_row_replaced`
blocks the old Agent from attaching to the new row. An in-flight durable continuation keeps its original row
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
action's `touches_resources` option. Use dedicated read and update actions
with no custom action or transaction hooks. AshJido rejects registered hooks
before running the action. Keep custom changes and nested operations on the
same repo. Use an outbox for effects that must follow the commit. If a
projected calculation or relationship depends on another row, make its writers
advance the bound row's version to detect concurrent changes. SQLite and PostgreSQL are supported. Context-per-tenant
databases and separate read or write repos cannot take part in this feature.

## Use JSON definitions

The Elixir `ash` declaration supplies the schema. JSON can reference the
compiled Agent and its inferred schema through the Catalog. A different
registered schema fails validation. JSON Schema describes supported scalar
fields. Ash still validates the full projection at runtime.

## Run the integration tests

`mix test` runs the SQLite tests with a temporary database file. To also
run the PostgreSQL tests, set `ASH_JIDO_POSTGRES_PORT` to the port of a test
server. The tests use `localhost` with the `postgres` user by default. They
create and remove a separate database for each test.
