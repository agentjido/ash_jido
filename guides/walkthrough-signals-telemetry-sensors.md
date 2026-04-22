# Walkthrough: Signals, Telemetry, and Sensors

This walkthrough covers the operational integration points:

1. Emit Jido signals from Ash notifications.
2. Override signal dispatch at runtime.
3. Subscribe to Jido-namespaced telemetry.
4. Forward dispatched signals into `Jido.Sensor.Runtime`.

## 1. Enable Signals and Telemetry in DSL

```elixir
jido do
  action :create,
    emit_signals?: true,
    signal_dispatch: {:noop, []},
    telemetry?: true

  action :update,
    emit_signals?: true,
    signal_dispatch: {:noop, []},
    signal_type: "my_app.post.updated",
    signal_source: "/my_app/posts",
    telemetry?: true
end
```

Behavior is opt-in:

- No signals are emitted unless `emit_signals?` is `true`.
- No telemetry is emitted unless `telemetry?` is `true`.

`AshJido.Notifier` remains the recommended Ash-native path for resource lifecycle publications to
a Jido signal bus. Generated actions use the same `AshJido.SignalFactory` payload builder when
`emit_signals?` is enabled, then dispatch the signal through `signal_dispatch`.

Both paths produce the same envelope conventions:

- `signal.type` is `{prefix}.{resource_short_name}.{action_name}` unless explicitly overridden.
- `signal.source` follows `/ash/{resource_short_name}/{action_type}/{action_name}` unless explicitly overridden.
- `signal.subject` identifies the primary key as `/{resource_short_name}/{id}` when available.
- `signal.extensions["jido_metadata"]` includes Ash resource, action, action type, and timestamp metadata.

Generated-action signals put all available Ash attributes in `signal.data`. Notifier publications
use the publication `include` mode (`:pkey_only`, `:all`, `:changes_only`, or selected fields).

## 2. Dispatch to a Runtime Target

Runtime context can override DSL dispatch configuration:

```elixir
context = %{
  domain: MyApp.Blog,
  signal_dispatch: {:pid, target: self()}
}

{:ok, _post} = MyApp.Blog.Post.Jido.Create.run(%{title: "Hello", author_id: id}, context)

assert_receive {:signal, %Jido.Signal{} = signal}
signal.type
signal.source
signal.data
```

If signaling is enabled and no dispatch config can be resolved (DSL or context), execution fails early with a validation-style error.

## 3. Subscribe to Telemetry

Generated actions emit these telemetry events when enabled:

- `[:jido, :action, :ash_jido, :start]`
- `[:jido, :action, :ash_jido, :stop]`
- `[:jido, :action, :ash_jido, :exception]`

```elixir
:telemetry.attach_many(
  "ash-jido-observer",
  [
    [:jido, :action, :ash_jido, :start],
    [:jido, :action, :ash_jido, :stop],
    [:jido, :action, :ash_jido, :exception]
  ],
  fn event, measurements, metadata, _config ->
    IO.inspect({event, measurements, metadata}, label: "ash_jido_telemetry")
  end,
  nil
)
```

`stop` and `exception` events include `:duration` and `result_status` metadata (`:ok` or `:error`).

## 4. Bridge Dispatch Messages to Sensors

`AshJido.SensorDispatchBridge` accepts common signal envelopes and forwards them to `Jido.Sensor.Runtime.event/2`:

```elixir
# forward one
:ok = AshJido.SensorDispatchBridge.forward({:signal, signal}, sensor_runtime)

# forward many
%{forwarded: count, errors: errors} =
  AshJido.SensorDispatchBridge.forward_many([
    signal,
    {:signal, signal},
    :not_a_signal
  ], sensor_runtime)

# mailbox-safe variant
:ok | :ignored | {:error, :runtime_unavailable} =
  AshJido.SensorDispatchBridge.forward_or_ignore(message, sensor_runtime)
```

Supported envelopes for `forward/2`:

- `%Jido.Signal{}`
- `{:signal, %Jido.Signal{}}`
- `{:signal, {:ok, %Jido.Signal{}}}`
