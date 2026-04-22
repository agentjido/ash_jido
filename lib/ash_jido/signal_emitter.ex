defmodule AshJido.SignalEmitter do
  @moduledoc false

  require Logger

  alias Jido.Action.Error
  alias Jido.Signal

  @doc false
  @spec validate_dispatch_config(map(), struct(), module(), atom(), atom()) ::
          :ok | {:error, Exception.t()}
  def validate_dispatch_config(_context, jido_config, _resource, _action_name, action_type)
      when action_type not in [:create, :update, :destroy] do
    _ = jido_config
    :ok
  end

  def validate_dispatch_config(context, jido_config, resource, action_name, _action_type) do
    if jido_config.emit_signals? do
      case resolve_dispatch_config(context, jido_config) do
        nil ->
          {:error,
           Error.validation_error(
             "AshJido: signal dispatch configuration is required when emit_signals? is enabled for #{inspect(resource)}.#{action_name}",
             %{field: :signal_dispatch}
           )}

        dispatch ->
          case Jido.Signal.Dispatch.validate_opts(dispatch) do
            {:ok, _} ->
              :ok

            {:error, reason} ->
              {:error,
               Error.validation_error(
                 "AshJido: invalid signal dispatch configuration",
                 %{field: :signal_dispatch, reason: reason}
               )}
          end
      end
    else
      :ok
    end
  end

  @doc false
  @spec emit_notifications(
          [Ash.Notifier.Notification.t()],
          map(),
          module(),
          atom(),
          struct()
        ) :: %{sent: non_neg_integer(), failed: [map()]}
  def emit_notifications(notifications, context, resource, action_name, jido_config) do
    dispatch = resolve_dispatch_config(context, jido_config)

    notifications
    |> List.wrap()
    |> Enum.reduce(%{sent: 0, failed: []}, fn notification, acc ->
      notification = ensure_action_name(notification, action_name)

      with {:ok, signal} <-
             AshJido.SignalFactory.from_notification(notification, jido_config),
           %{sent: 1, failed: []} <- emit_signals([signal], dispatch, resource, action_name) do
        %{acc | sent: acc.sent + 1}
      else
        %{sent: 0, failed: [failure]} ->
          %{acc | failed: [Map.put(failure, :notification, notification) | acc.failed]}

        {:error, reason} ->
          failure = %{
            reason: reason,
            notification: notification
          }

          Logger.warning("AshJido failed to emit signal for #{inspect(resource)}.#{action_name}: #{inspect(reason)}")

          %{acc | failed: [failure | acc.failed]}
      end
    end)
    |> Map.update!(:failed, &Enum.reverse/1)
  end

  @doc false
  @spec emit_signals([Signal.t()], term(), module(), atom()) :: %{sent: non_neg_integer(), failed: [map()]}
  def emit_signals(signals, dispatch, resource, action_name) do
    signals
    |> List.wrap()
    |> Enum.reduce(%{sent: 0, failed: []}, fn signal, acc ->
      case dispatch_signal(signal, dispatch) do
        :ok ->
          %{acc | sent: acc.sent + 1}

        {:error, reason} ->
          failure = %{
            reason: reason,
            signal: signal
          }

          Logger.warning(
            "AshJido failed to dispatch signal for #{inspect(resource)}.#{action_name}: #{inspect(reason)}"
          )

          %{acc | failed: [failure | acc.failed]}
      end
    end)
    |> Map.update!(:failed, &Enum.reverse/1)
  end

  @doc false
  @spec resolve_dispatch_config(map(), struct()) :: term() | nil
  def resolve_dispatch_config(context, jido_config) do
    if Map.has_key?(context, :signal_dispatch) do
      Map.get(context, :signal_dispatch)
    else
      jido_config.signal_dispatch
    end
  end

  defp ensure_action_name(%Ash.Notifier.Notification{action: %{name: name}} = notification, _action_name)
       when not is_nil(name),
       do: notification

  defp ensure_action_name(%Ash.Notifier.Notification{action: action} = notification, action_name)
       when is_map(action) do
    %{notification | action: Map.put(action, :name, action_name)}
  end

  defp ensure_action_name(%Ash.Notifier.Notification{} = notification, action_name) do
    %{notification | action: %{name: action_name, type: nil}}
  end

  defp dispatch_signal(_signal, nil), do: {:error, :missing_dispatch}

  defp dispatch_signal(signal, {:ash_jido_bus, bus}) do
    case Jido.Signal.Bus.publish(bus, [signal]) do
      {:ok, _recorded_signals} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp dispatch_signal(signal, dispatch) do
    case Jido.Signal.Dispatch.dispatch(signal, dispatch) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
