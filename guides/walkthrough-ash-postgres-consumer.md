# Walkthrough: AshPostgres Consumer Integration Harness

This walkthrough documents the canonical real integration harness at `ash_jido_consumer/`.

It is the reference app for validating AshJido behavior against a real Postgres data layer.

## 1. Local Setup

```bash
cd ash_jido_consumer
mix deps.get
mix ecto.setup
mix test
```

Notes:

- `mix test` in this app also runs `ecto.create` and `ecto.migrate` via test aliases.
- DB defaults can be overridden with `ASH_JIDO_CONSUMER_DB_*` env vars.

## 2. Domain and Resource Layout

The consumer app is intentionally a single app with focused domains:

- `AshJidoConsumer.Accounts`
  - `AshJidoConsumer.Accounts.User` (policy-aware create/read + runtime context actions)
- `AshJidoConsumer.Content`
  - `AshJidoConsumer.Content.Author`
  - `AshJidoConsumer.Content.Post` (signals, telemetry, relationship read load)
- `AshJidoConsumer.Tenanting`
  - `AshJidoConsumer.Tenanting.Note` (attribute multitenancy)

## 3. End-to-End Flows Verified

### Full CRUD via generated actions

```elixir
{:ok, author} =
  AshJidoConsumer.Content.Author
  |> Ash.Changeset.for_create(:create, %{name: "Ada"}, domain: AshJidoConsumer.Content)
  |> Ash.create(domain: AshJidoConsumer.Content)

{:ok, created} =
  AshJidoConsumer.Content.Post.Jido.Create.run(
    %{title: "Guide Post", author_id: author.id},
    %{domain: AshJidoConsumer.Content, signal_dispatch: {:noop, []}}
  )

{:ok, updated} =
  AshJidoConsumer.Content.Post.Jido.Update.run(
    %{id: created[:id], title: "Guide Post Updated"},
    %{domain: AshJidoConsumer.Content, signal_dispatch: {:noop, []}}
  )

{:ok, %{deleted: true}} =
  AshJidoConsumer.Content.Post.Jido.Destroy.run(
    %{id: updated[:id]},
    %{domain: AshJidoConsumer.Content, signal_dispatch: {:noop, []}}
  )
```

### Policy actor via scope

```elixir
{:ok, user} =
  AshJidoConsumer.Accounts.User.Jido.Create.run(
    %{name: "Scope User", email: "scope-user@example.com"},
    %{domain: AshJidoConsumer.Accounts, scope: %{actor: %{id: "scope_actor"}}}
  )

user[:email] # => "scope-user@example.com"
```

### Relationship-aware read load

```elixir
{:ok, posts} =
  AshJidoConsumer.Content.Post.Jido.Read.run(
    %{},
    %{domain: AshJidoConsumer.Content}
  )

Enum.at(posts, 0)[:author]
```

### Signals + telemetry

```elixir
:telemetry.attach_many(
  "consumer-guide",
  [
    [:jido, :action, :ash_jido, :start],
    [:jido, :action, :ash_jido, :stop],
    [:jido, :action, :ash_jido, :exception]
  ],
  fn event, measurements, metadata, _ ->
    IO.inspect({event, measurements, metadata}, label: "consumer_telemetry")
  end,
  nil
)

{:ok, _post} =
  AshJidoConsumer.Content.Post.Jido.Create.run(
    %{title: "Signal Post", author_id: author_id},
    %{domain: AshJidoConsumer.Content, signal_dispatch: {:pid, target: self()}}
  )

assert_receive {:signal, %Jido.Signal{}}
```

## 4. CI Execution Model

The root CI includes a dedicated `Consumer Integration (AshPostgres)` job that:

1. Starts `postgres:16` service.
2. Installs dependencies in `ash_jido_consumer/`.
3. Runs `mix format --check-formatted` in `ash_jido_consumer/`.
4. Runs `mix test` in `ash_jido_consumer/`.

This keeps consumer verification behavior-driven and separate from root ETS-only test coverage.
