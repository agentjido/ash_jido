defmodule AshJido.SignalFactory do
  @moduledoc """
  Converts Ash notifier notifications into `Jido.Signal` structs.

  Signal payloads contain only explicitly selected public, non-sensitive
  resource fields. Optional structured Ash metadata is stored under the
  `:ash_jido` data key because CloudEvents extensions accept scalar values
  only.
  """

  alias Ash.Notifier.Notification
  alias AshJido.Publication
  alias Jido.Signal

  @type reason :: term()

  @doc """
  Builds a `Jido.Signal` from an Ash notifier notification and signal configuration.
  """
  @spec from_notification(Notification.t(), Publication.t()) ::
          {:ok, Signal.t()} | {:error, reason()}
  def from_notification(%Notification{} = notification, %Publication{} = publication) do
    signal_data =
      notification
      |> build_signal_data(publication)
      |> put_ash_metadata(build_metadata(notification, publication))

    Signal.new(%{
      type: publication.signal_type,
      source: build_source(notification),
      data: signal_data,
      subject: subject_from_notification(notification)
    })
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
    |> public_signal_attributes()
    |> Enum.reduce(%{}, fn attribute, acc ->
      case fetch_value(data, attribute.name) do
        {:ok, value} -> Map.put(acc, attribute.name, normalize_value(value))
        :error -> acc
      end
    end)
  end

  defp extract_changes(%Notification{changeset: %Ash.Changeset{} = changeset} = notification) do
    allowed =
      notification.resource
      |> public_signal_attributes()
      |> MapSet.new(& &1.name)

    changeset
    |> Map.get(:attributes, %{})
    |> Enum.filter(fn {key, _value} -> MapSet.member?(allowed, key) end)
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      resolved_value =
        case fetch_value(notification.data, key) do
          {:ok, data_value} -> data_value
          :error -> value
        end

      Map.put(acc, key, normalize_value(resolved_value))
    end)
  end

  defp extract_changes(_notification), do: %{}

  defp extract_selected_attributes(%Notification{data: nil}, _fields), do: %{}

  defp extract_selected_attributes(%Notification{data: data}, fields) do
    Enum.reduce(fields, %{}, fn field, acc ->
      case fetch_value(data, field) do
        {:ok, value} -> Map.put(acc, field, normalize_value(value))
        :error -> acc
      end
    end)
  end

  defp extract_primary_key(%Notification{data: nil}), do: %{}

  defp extract_primary_key(%Notification{data: data, resource: resource}) do
    resource
    |> Ash.Resource.Info.primary_key()
    |> Enum.reduce(%{}, fn key, acc ->
      case fetch_value(data, key) do
        {:ok, value} -> Map.put(acc, key, normalize_value(value))
        :error -> acc
      end
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
      |> Enum.reduce([], fn key, acc ->
        case fetch_value(data, key) do
          {:ok, nil} -> acc
          {:ok, value} -> [to_string(value) | acc]
          :error -> acc
        end
      end)
      |> Enum.reverse()

    if pkey_values == [] do
      nil
    else
      "/#{resource_short_name(resource)}/#{Enum.join(pkey_values, ":")}"
    end
  end

  defp build_metadata(%Notification{} = notification, %Publication{} = publication) do
    %{}
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
            AshJido.Serializer.serialize(data)

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
    case Map.fetch(data, key) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        Map.fetch(data, to_string(key))
    end
  end

  defp fetch_value(_, _), do: :error

  defp normalize_value(value), do: AshJido.Serializer.serialize(value)

  defp put_ash_metadata(data, metadata) when map_size(metadata) == 0, do: data
  defp put_ash_metadata(data, metadata), do: Map.put(data, :ash_jido, metadata)

  defp public_signal_attributes(resource) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.reject(& &1.sensitive?)
  end
end
