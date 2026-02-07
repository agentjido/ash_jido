defmodule AshJido.SignalFactory do
  @moduledoc """
  Converts Ash notifier notifications into `Jido.Signal` structs.

  Auto-derived signal types follow:

      {prefix}.{resource_short_name}.{action_name}

  Prefix resolution order:
  1. resource-level `jido signal_prefix` DSL option
  2. `config :ash_jido, :signal_prefix`
  3. default `"ash"`
  """

  alias Ash.Notifier.Notification
  alias AshJido.Publication
  alias Jido.Signal

  @type reason :: term()

  @doc """
  Builds a `Jido.Signal` from an Ash notifier notification and publication config.
  """
  @spec from_notification(Notification.t(), Publication.t()) ::
          {:ok, Signal.t()} | {:error, reason()}
  def from_notification(%Notification{} = notification, %Publication{} = publication) do
    signal_type = resolve_signal_type(notification, publication)
    signal_data = build_signal_data(notification, publication)
    signal_source = build_source(notification)
    signal_metadata = build_metadata(notification, publication)

    with {:ok, signal} <-
           Signal.new(%{
             type: signal_type,
             source: signal_source,
             data: signal_data,
             subject: subject_from_notification(notification)
           }) do
      {:ok, put_jido_metadata(signal, signal_metadata)}
    end
  end

  defp resolve_signal_type(_notification, %Publication{signal_type: explicit})
       when is_binary(explicit),
       do: explicit

  defp resolve_signal_type(%Notification{} = notification, _publication) do
    prefix = resource_prefix(notification.resource)
    short_name = resource_short_name(notification.resource)
    action_name = notification.action.name

    "#{prefix}.#{short_name}.#{action_name}"
  end

  defp resource_prefix(resource) do
    case AshJido.Info.signal_prefix(resource) do
      {:ok, prefix} when is_binary(prefix) and prefix != "" ->
        prefix

      _ ->
        Application.get_env(:ash_jido, :signal_prefix, "ash")
    end
  end

  defp resource_short_name(resource) do
    resource
    |> Ash.Resource.Info.short_name()
    |> to_string()
  end

  defp build_signal_data(notification, %Publication{include: :all}) do
    extract_all_attributes(notification)
  end

  defp build_signal_data(notification, %Publication{include: :changes_only}) do
    extract_changes(notification)
  end

  defp build_signal_data(notification, %Publication{include: fields}) when is_list(fields) do
    extract_selected_attributes(notification, fields)
  end

  defp build_signal_data(notification, _publication) do
    extract_primary_key(notification)
  end

  defp extract_all_attributes(%Notification{data: nil}), do: %{}

  defp extract_all_attributes(%Notification{data: data, resource: resource}) do
    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.reduce(%{}, fn attribute, acc ->
      case fetch_value(data, attribute.name) do
        nil -> acc
        value -> Map.put(acc, attribute.name, normalize_value(value))
      end
    end)
  end

  defp extract_changes(%Notification{changeset: %Ash.Changeset{} = changeset}) do
    changeset
    |> Map.get(:attributes, %{})
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, key, normalize_value(value))
    end)
  end

  defp extract_changes(_notification), do: %{}

  defp extract_selected_attributes(%Notification{data: nil}, _fields), do: %{}

  defp extract_selected_attributes(%Notification{data: data}, fields) do
    Enum.reduce(fields, %{}, fn field, acc ->
      case fetch_value(data, field) do
        nil -> acc
        value -> Map.put(acc, field, normalize_value(value))
      end
    end)
  end

  defp extract_primary_key(%Notification{data: nil}), do: %{}

  defp extract_primary_key(%Notification{data: data, resource: resource}) do
    resource
    |> Ash.Resource.Info.primary_key()
    |> Enum.reduce(%{}, fn key, acc ->
      Map.put(acc, key, normalize_value(fetch_value(data, key)))
    end)
  end

  defp build_source(%Notification{} = notification) do
    short_name = resource_short_name(notification.resource)
    action_type = notification.action.type
    action_name = notification.action.name

    "/ash/#{short_name}/#{action_type}/#{action_name}"
  end

  defp subject_from_notification(%Notification{data: nil}), do: nil

  defp subject_from_notification(%Notification{data: data, resource: resource}) do
    pkey_values =
      resource
      |> Ash.Resource.Info.primary_key()
      |> Enum.map(&fetch_value(data, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)

    if pkey_values == [] do
      nil
    else
      "/#{resource_short_name(resource)}/#{Enum.join(pkey_values, ":")}"
    end
  end

  defp build_metadata(%Notification{} = notification, %Publication{} = publication) do
    base = %{
      ash_resource: notification.resource,
      ash_action: notification.action.name,
      ash_action_type: notification.action.type,
      timestamp: DateTime.utc_now()
    }

    base
    |> maybe_add_actor(notification, publication)
    |> maybe_add_tenant(notification, publication)
    |> maybe_add_changes(notification, publication)
    |> maybe_add_previous_state(notification, publication)
  end

  defp maybe_add_actor(metadata, notification, publication) do
    if :actor in metadata_fields(publication) and not is_nil(notification.actor) do
      actor_id =
        case notification.actor do
          %{id: id} -> id
          %{"id" => id} -> id
          other -> other
        end

      Map.put(metadata, :actor_id, normalize_value(actor_id))
    else
      metadata
    end
  end

  defp maybe_add_tenant(metadata, %Notification{} = notification, publication) do
    if :tenant in metadata_fields(publication) do
      case notification.changeset do
        %Ash.Changeset{tenant: tenant} when not is_nil(tenant) ->
          Map.put(metadata, :tenant, tenant)

        _ ->
          metadata
      end
    else
      metadata
    end
  end

  defp maybe_add_changes(metadata, %Notification{} = notification, publication) do
    if :changes in metadata_fields(publication) do
      Map.put(metadata, :changes, extract_changes(notification))
    else
      metadata
    end
  end

  defp maybe_add_previous_state(metadata, %Notification{} = notification, publication) do
    if :previous_state in metadata_fields(publication) do
      previous_state =
        case notification do
          %Notification{changeset: %Ash.Changeset{data: data}} when not is_nil(data) ->
            normalize_value(data)

          _ ->
            nil
        end

      Map.put(metadata, :previous_state, previous_state)
    else
      metadata
    end
  end

  defp metadata_fields(%Publication{metadata: fields}) when is_list(fields), do: fields
  defp metadata_fields(_), do: []

  defp fetch_value(data, key) when is_map(data) do
    case data do
      %{^key => value} ->
        value

      _ ->
        Map.get(data, to_string(key))
    end
  end

  defp fetch_value(_, _), do: nil

  defp normalize_value(%Date{} = value), do: value
  defp normalize_value(%Time{} = value), do: value
  defp normalize_value(%NaiveDateTime{} = value), do: value
  defp normalize_value(%DateTime{} = value), do: value
  defp normalize_value(list) when is_list(list), do: Enum.map(list, &normalize_value/1)

  defp normalize_value(%_{} = struct) do
    module = struct.__struct__

    case Atom.to_string(module) do
      "Elixir.Ash.CiString" ->
        Map.get(struct, :string)

      _ ->
        struct
        |> Map.from_struct()
        |> Enum.reduce(%{}, fn {key, value}, acc ->
          if internal_key?(key) do
            acc
          else
            Map.put(acc, key, normalize_value(value))
          end
        end)
    end
  end

  defp normalize_value(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      Map.put(acc, key, normalize_value(value))
    end)
  end

  defp normalize_value(value), do: value

  defp internal_key?(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.starts_with?("__")
  end

  defp internal_key?(_), do: false

  defp put_jido_metadata(signal, metadata) do
    extensions =
      signal
      |> Map.get(:extensions, %{})
      |> case do
        map when is_map(map) -> map
        _ -> %{}
      end

    Map.put(signal, :extensions, Map.put(extensions, "jido_metadata", metadata))
  end
end
