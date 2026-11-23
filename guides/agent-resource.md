# Expose a live Jido Agent through Ash

Add the `AshJido.Agent` extension to an Ash resource. List the lifecycle
operations, routes, and fields that the resource exposes.

```elixir
defmodule MyApp.Automation.Counter do
  use Ash.Resource,
    domain: MyApp.Automation,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJido.Agent]

  jido_agent do
    agent MyApp.CounterAgent
    instance MyApp.Jido
    expose_lifecycle [:start, :activate, :inspect, :status, :stop]
    expose_routes [:increment]
    expose_state [:count]
  end

  policies do
    policy always() do
      authorize_if actor_present()
    end
  end
end
```

Ash evaluates policies before it calls Jido. Pass a `Jido.Agent.Address` or its
portable map as the `address` argument to each action.

```elixir
{:ok, address} = Jido.agent_address(MyApp.Jido, "counter-1", partition: "east")

MyApp.Automation.Counter
|> Ash.ActionInput.for_action(:inspect, %{address: address}, actor: actor)
|> Ash.run_action(actor: actor, authorize?: true)
```

## Lifecycle and state

- `start` starts a new Agent of the declared type. `activate` restores an
  existing durable Agent of that type or returns its current active address.
- `status` returns a compact runtime status. `stop` drains and stops the resident
  activation.
- `inspect` returns one Ash resource value from one atomic committed snapshot.
  Its `id`, `partition`, and `state_version` identify the projected state.
  The version is Jido's Agent revision. The projection includes only the
  declared domain fields.

The resource is a projection. Use the generated `inspect` action to read one
Agent. The extension creates no Ash read action or data layer. Jido owns its
runtime, state, Plugins, and checkpoints. The names `hibernate` and `delete`
are reserved for future lifecycle operations.

## Named routes

Each exposed route must have an exact Signal type, an `as:` alias, and an
Action or Flow handler. The Signal type must match only that route. The
extension maps ordinary Action object schemas to
Ash arguments. It supports common scalar values, atom and string enums, arrays,
maps, and nested objects. Supply explicit Ash arguments for unsupported schemas
or Flows.

```elixir
route_arguments increment: [amount: [type: :integer, allow_nil?: false]]
```

Jido builds and admits the Signal and validates the Turn. The Ash result
contains its address, Turn ID, status, state version, and effects status. When
the result says `:committed`, Jido has committed the state. Post-commit effects
can still be pending.

## Caller context and durable Turns

Caller context is separate from Agent state. A pending durable Flow can store
caller context in its Turn receipt. Keep complete actor records and credentials
out of that context. Use a binary tenant and a stable actor reference with
binary `:type` and `:id` fields.

Implement the `AshJido.ActorScope` callbacks in your application and configure
`config :ash_jido, :actor_resolver, MyApp.ActorResolver`. The generated route
action calls `reference/2` after Ash authorization. AshJido calls
`resolve_actor/2` just before it needs to make an Ash call. For Signals sent
outside an Ash generic action, use `AshJido.ActorScope.caller_context/2` to
build the same context. `authorize?: false` is invalid.
