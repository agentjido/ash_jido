defmodule AshJido.SignalEmitter do
  @moduledoc false

  require Logger

  alias Jido.Action.Error

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
      with {:ok, signal} <-
             notification_to_signal(notification, resource, action_name, jido_config),
           :ok <- dispatch_signal(signal, dispatch) do
        %{acc | sent: acc.sent + 1}
      else
        {:error, reason} ->
          failure = %{
            reason: reason,
            notification: notification
          }

          Logger.warning(
            "AshJido failed to emit signal for #{inspect(resource)}.#{action_name}: #{inspect(reason)}"
          )

          %{acc | failed: [failure | acc.failed]}
      end
    end)
    |> Map.update!(:failed, &Enum.reverse/1)
  end

  @spec resolve_dispatch_config(map(), struct()) :: term() | nil
  def resolve_dispatch_config(context, jido_config) do
    if Map.has_key?(context, :signal_dispatch) do
      Map.get(context, :signal_dispatch)
    else
      jido_config.signal_dispatch
    end
  end

  defp notification_to_signal(notification, resource, action_name, jido_config) do
    signal_type = jido_config.signal_type || default_signal_type(resource, action_name)
    source = jido_config.signal_source || default_signal_source(resource)
    subject = extract_subject(notification.data)

    attrs =
      [source: source]
      |> maybe_put_subject(subject)

    data = %{
      action: action_name,
      action_type: extract_action_type(notification),
      metadata: notification.metadata,
      resource: resource,
      result: notification.data
    }

    Jido.Signal.new(signal_type, data, attrs)
  end

  defp dispatch_signal(_signal, nil), do: {:error, :missing_dispatch}

  defp dispatch_signal(signal, dispatch) do
    case Jido.Signal.Dispatch.dispatch(signal, dispatch) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put_subject(attrs, nil), do: attrs
  defp maybe_put_subject(attrs, subject), do: Keyword.put(attrs, :subject, subject)

  defp default_signal_type(resource, action_name) do
    resource_segment =
      resource
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    "ash_jido.#{resource_segment}.#{action_name}"
  end

  defp default_signal_source(resource) do
    resource_segments =
      resource
      |> Module.split()
      |> Enum.map(&Macro.underscore/1)
      |> Enum.join("/")

    "/ash_jido/#{resource_segments}"
  end

  defp extract_subject(%{id: id}) when not is_nil(id), do: to_string(id)
  defp extract_subject(%{id: id}) when is_nil(id), do: nil
  defp extract_subject(%_{} = struct), do: extract_subject(Map.from_struct(struct))
  defp extract_subject(_), do: nil

  defp extract_action_type(notification) do
    case notification.action do
      %{type: type} -> type
      _ -> nil
    end
  end
end
