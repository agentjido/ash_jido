# Jido Signal publications

AshJido publishes resource events through one path: an Ash notifier sends explicit publications to `Jido.Signal.Bus`.

Generated Actions do not emit a second event. This prevents two signals for one Ash operation.

## Configure a resource

```elixir
defmodule MyApp.Blog.Post do
  use Ash.Resource,
    domain: MyApp.Blog,
    extensions: [AshJido],
    notifiers: [AshJido.Notifier]

  jido do
    signal_bus MyApp.SignalBus

    publish :create, "blog.post.created",
      include: [:id, :title],
      metadata: [:actor, :tenant]

    publish [:update, :publish], "blog.post.changed",
      include: :changes_only,
      metadata: [:changes, :previous_state]
  end
end
```

Each publication needs an explicit signal type. `signal_bus` can be a bus name or an MFA that returns the bus. If the resource does not set it, the notifier reads `config :ash_jido, :signal_bus`.

The application must start and supervise the Jido Signal bus.

## Select data

`include` supports these values:

- `:pkey_only` includes the primary key. This is the default.
- A list of fields includes only those fields.
- `:changes_only` includes changed public fields.
- `:all` includes all public fields.

Explicit fields must be public and non-sensitive. `:all` and `:changes_only` also remove private and sensitive fields. Unloaded and forbidden values are not serialized.

## Add Ash metadata

`metadata` can include:

- `:actor`
- `:tenant`
- `:changes`
- `:previous_state`

Structured metadata is available at `signal.data[:ash_jido]`. It is not stored in `signal.extensions`. Jido v3 follows the CloudEvents rule that extension values must be scalar.

Example payload:

```elixir
%Jido.Signal{
  type: "blog.post.created",
  source: "/ash/post/create/create",
  subject: "/post/7f2b...",
  data: %{
    id: "7f2b...",
    title: "Hello",
    ash_jido: %{actor_id: "user-1", tenant: "tenant-1"}
  }
}
```

The Signal `source` states the Ash resource, action type, and action name. The `subject` contains the resource short name and primary key values.

## Conditions

A publication can use a condition:

```elixir
publish :update, "blog.post.published",
  include: [:id, :status],
  condition: fn notification ->
    notification.data && notification.data.status == :published
  end
```

The notifier logs and skips a publication when its condition raises or signal construction fails. A bus publication failure emits `[:ash_jido, :signal, :publication_failed]` telemetry and is logged. It does not change the completed Ash result.

Use an outbox in the application when it needs transactional, durable event delivery. A direct notifier publication is not a database outbox.
