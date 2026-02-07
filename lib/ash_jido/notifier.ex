defmodule AshJido.Notifier do
  @moduledoc """
  Ash notifier that publishes Jido signals when configured resource actions complete.

  Add this notifier to resource definitions to enable reactive publications:

      use Ash.Resource,
        extensions: [AshJido],
        notifiers: [AshJido.Notifier]

      jido do
        signal_bus MyApp.SignalBus
        publish :create, "my_app.resource.created"
      end
  """

  use Ash.Notifier

  require Logger

  @impl Ash.Notifier
  def notify(%Ash.Notifier.Notification{} = notification) do
    resource = notification.resource
    action_name = notification.action.name

    with {:ok, publications} <- matching_publications(resource, action_name),
         {:ok, bus} <- signal_bus(resource) do
      signals =
        publications
        |> Enum.filter(&passes_condition?(&1, notification))
        |> Enum.flat_map(fn publication ->
          case AshJido.SignalFactory.from_notification(notification, publication) do
            {:ok, signal} ->
              [signal]

            {:error, reason} ->
              Logger.warning(
                "AshJido.Notifier failed to build signal for #{inspect(resource)}.#{action_name}: #{inspect(reason)}"
              )

              []
          end
        end)

      publish_signals(bus, signals)
    else
      {:error, :no_publications} ->
        :ok

      {:error, :no_signal_bus} ->
        Logger.warning(
          "AshJido.Notifier has no signal bus configured for #{inspect(resource)}. " <>
            "Set `signal_bus` in the `jido` DSL block or `config :ash_jido, :signal_bus`."
        )

        :ok

      {:error, {:invalid_signal_bus_mfa, mfa, reason}} ->
        Logger.error(
          "AshJido.Notifier failed resolving signal bus MFA #{inspect(mfa)}: #{inspect(reason)}"
        )

        :ok
    end
  end

  @impl Ash.Notifier
  def requires_original_data?(resource, action) do
    case AshJido.Info.publications(resource) do
      {:ok, publications} ->
        publications
        |> Enum.filter(&(action.name in (&1.actions || [])))
        |> Enum.any?(&requires_original_data_for_publication?/1)

      _ ->
        false
    end
  end

  defp requires_original_data_for_publication?(publication) do
    publication.include in [:all, :pkey_only] or
      :previous_state in List.wrap(publication.metadata)
  end

  defp matching_publications(resource, action_name) do
    case AshJido.Info.publications(resource) do
      {:ok, publications} ->
        publications
        |> Enum.filter(&(action_name in (&1.actions || [])))
        |> case do
          [] -> {:error, :no_publications}
          matched -> {:ok, matched}
        end

      _ ->
        {:error, :no_publications}
    end
  end

  defp signal_bus(resource) do
    case AshJido.Info.signal_bus(resource) do
      {:ok, configured_bus} ->
        resolve_bus(configured_bus)

      _ ->
        Application.get_env(:ash_jido, :signal_bus)
        |> resolve_bus()
    end
  end

  defp resolve_bus(nil), do: {:error, :no_signal_bus}

  defp resolve_bus({module, function, args} = mfa)
       when is_atom(module) and is_atom(function) and is_list(args) do
    try do
      case apply(module, function, args) do
        nil -> {:error, :no_signal_bus}
        bus -> {:ok, bus}
      end
    rescue
      error -> {:error, {:invalid_signal_bus_mfa, mfa, error}}
    end
  end

  defp resolve_bus(bus), do: {:ok, bus}

  defp publish_signals(_bus, []), do: :ok

  defp publish_signals(bus, signals) do
    case Jido.Signal.Bus.publish(bus, signals) do
      {:ok, _recorded_signals} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "AshJido.Notifier failed to publish signals to #{inspect(bus)}: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp passes_condition?(%{condition: nil}, _notification), do: true

  defp passes_condition?(%{condition: condition}, notification) when is_function(condition, 1) do
    try do
      condition.(notification) == true
    rescue
      error ->
        Logger.warning("AshJido.Notifier publication condition raised: #{inspect(error)}")
        false
    end
  end

  defp passes_condition?(_publication, _notification), do: true
end
