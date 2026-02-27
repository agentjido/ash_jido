# Walkthrough: Failure Semantics and Error Contracts

This walkthrough documents how generated AshJido actions fail and what callers should expect.

## 1. Error Mapping

AshJido maps Ash failures to Jido action errors.

| Failure Source | Typical Jido Error | Notes |
|---|---|---|
| Validation/input failures (`Ash.Error.Invalid`) | `Jido.Action.Error.InvalidInputError` | Field-level details are preserved in `error.details` |
| Authorization failures (`Ash.Error.Forbidden`) | `Jido.Action.Error.ExecutionFailureError` | `error.details.reason` is commonly `:forbidden` |
| Runtime/framework/unknown failures | `Jido.Action.Error.InternalError` | Includes wrapped Ash/context error details |

## 2. Deterministic Failure Cases

### Missing `domain`

Generated actions require `domain` in context and raise `ArgumentError` if omitted.

```elixir
assert_raise ArgumentError, ~r/:domain must be provided/, fn ->
  MyApp.Accounts.User.Jido.Read.run(%{}, %{})
end
```

### Missing `id` for update/destroy

```elixir
assert {:error, %Jido.Action.Error.ExecutionFailureError{} = error} =
  MyApp.Content.Post.Jido.Update.run(
    %{title: "missing id"},
    %{domain: MyApp.Content}
  )

error.message # => "Update actions require an 'id' parameter"
```

### Missing `signal_dispatch` when signaling is enabled

```elixir
assert {:error, %Jido.Action.Error.InvalidInputError{} = error} =
  MyApp.Content.Post.Jido.Create.run(
    %{title: "Missing dispatch", author_id: author_id},
    %{domain: MyApp.Content}
  )

String.contains?(error.message, "signal dispatch configuration is required")
```

### Dispatch failure after successful Ash operation

When signal dispatch fails after a successful write, the action result remains successful.

```elixir
missing_named_dispatch =
  {:named, [target: {:name, :missing_target}, delivery_mode: :sync]}

assert {:ok, created} =
  MyApp.Content.Post.Jido.Create.run(
    %{title: "Dispatch Failure", author_id: author_id},
    %{domain: MyApp.Content, signal_dispatch: missing_named_dispatch}
  )

created[:title] # => "Dispatch Failure"
```

## 3. Telemetry for Failures

With `telemetry?: true`, use stop/exception metadata to distinguish outcomes.

### Mapped error path (no exception)

- `[:jido, :action, :ash_jido, :start]`
- `[:jido, :action, :ash_jido, :stop]` with `result_status: :error`

### Exception path

- `[:jido, :action, :ash_jido, :start]`
- `[:jido, :action, :ash_jido, :exception]` with:
  - `result_status: :error`
  - `error_kind`
  - `error_reason`
  - `error_stacktrace`

### Signal delivery metadata

Stop metadata includes signal outcome counters:

- `signal_sent_count`
- `signal_failed_count`
- `signal_failures` (when failures occur)

These let you keep write success semantics while monitoring downstream dispatch health.
