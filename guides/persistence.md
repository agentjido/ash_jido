# Ash persistence adapter

`AshJido.Persistence.Adapter` implements the Jido v3 byte-store contract with a user-owned Ash resource.

Jido owns checkpoint encoding, record keys, revisions, tombstones, activation, hibernation, and recovery. AshJido stores only opaque binary keys and values.

## Define a store resource

```elixir
defmodule MyApp.JidoStore do
  use Ash.Resource,
    domain: MyApp.Infrastructure,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJido]

  postgres do
    table "jido_store"
    repo MyApp.Repo
  end

  jido do
    persistence_store()
  end
end
```

The transformer adds this private contract:

- binary primary key `:key`
- binary value `:value`
- binary compare-and-swap token `:write_token`
- fixed private read, create, atomic update, and destroy actions

Do not add public APIs for these fields. The adapter disables Ash authorization for this private infrastructure resource.

The data layer must support reads, creates, upserts, query updates, query destroys, and atomic updates. Compilation can succeed for any Ash data layer, but `AshJido.Persistence.StoreInfo.validate/1` rejects a resource that cannot meet the contract.

## Create the table

Create a migration with equivalent storage:

```elixir
create table(:jido_store, primary_key: false) do
  add :key, :binary, primary_key: true, null: false
  add :value, :binary, null: false
  add :write_token, :binary, null: false
end
```

Use the normal AshPostgres migration workflow for the application. AshJido does not own the repository or run migrations.

## Configure Jido

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    persistence: {
      AshJido.Persistence.Adapter,
      resource: MyApp.JidoStore
    }
end
```

The adapter also accepts `:domain`, `:tenant`, `:context`, and `:timeout`. The resource domain is used when `:domain` is not present.

## Atomic behavior

`get/2` returns the stored bytes and an opaque write token from one read. `compare_and_swap/4` changes the value and token in one atomic query update.

- `:not_found` creates only when the key is absent.
- `{:token, token}` matches the token from the last read.
- A binary expected value compares the stored bytes.
- A mismatch returns `{:error, :conflict}` and does not write.
- An unknown write result returns an indeterminate error.

The adapter never implements compare-and-swap as a separate read and write.

`put/3` and `delete/2` are unconditional maintenance operations. Jido checkpoint commits use `compare_and_swap/4`.

## Deployment rules

- Use a shared database for Agents that can run on more than one node.
- Ensure that all writers use a data layer with real atomic query updates.
- Keep the table and repository under application supervision.
- Treat an indeterminate write as a stop condition. Restore before another Action runs.
- Test conflict behavior against the production data layer before deployment.

The ETS data layer is useful for unit tests. It is not a durable production store.
