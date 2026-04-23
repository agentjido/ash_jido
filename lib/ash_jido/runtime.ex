defmodule AshJido.Runtime do
  @moduledoc false

  alias AshJido.ActionSpec

  @doc false
  @spec run(ActionSpec.t(), map(), map()) :: {:ok, term()} | {:error, term()}
  def run(%ActionSpec{} = spec, params, context) do
    ash_opts = AshJido.Context.extract_ash_opts!(context, spec.resource, spec.action_name)
    telemetry_meta = telemetry_metadata(spec, ash_opts)
    telemetry_span = AshJido.Telemetry.start(spec.config, telemetry_meta)

    {result, signal_meta, exception?} =
      case AshJido.SignalEmitter.validate_dispatch_config(
             context,
             spec.config,
             spec.resource,
             spec.action_name,
             spec.action_type
           ) do
        :ok ->
          execute_action(spec, params, context, ash_opts, telemetry_span)

        {:error, error} ->
          {{:error, error}, empty_signal_meta(), false}
      end

    if exception? do
      result
    else
      AshJido.Telemetry.stop(telemetry_span, result, signal_meta)
      result
    end
  end

  @doc false
  @spec fetch_primary_key!(map(), [atom()], atom()) :: term()
  def fetch_primary_key!(params, primary_key, action_type) do
    values =
      Map.new(primary_key, fn key ->
        {key, fetch_param(params, key)}
      end)

    missing_keys =
      values
      |> Enum.filter(fn {_key, value} -> is_nil(value) end)
      |> Enum.map(fn {key, _value} -> key end)

    unless Enum.empty?(missing_keys) do
      raise ArgumentError, missing_primary_key_message(action_type, primary_key)
    end

    case primary_key do
      [key] -> Map.fetch!(values, key)
      _ -> values
    end
  end

  @doc false
  @spec drop_primary_key_params(map(), [atom()]) :: map()
  def drop_primary_key_params(params, primary_key) do
    Enum.reduce(primary_key, params, fn key, acc ->
      Map.drop(acc, [key, to_string(key)])
    end)
  end

  defp execute_action(spec, params, context, ash_opts, telemetry_span) do
    try do
      do_execute_action(spec, params, context, ash_opts)
    rescue
      error -> handle_runtime_exception(error, __STACKTRACE__, telemetry_span)
    end
  end

  defp do_execute_action(%ActionSpec{action_type: :create} = spec, params, context, ash_opts) do
    create_result =
      spec.resource
      |> Ash.Changeset.for_create(spec.action_name, params, ash_opts)
      |> Ash.create!(maybe_add_notification_collection(ash_opts, spec.config, :create))

    {result, notifications} = maybe_extract_result_and_notifications(create_result)

    signal_emission =
      maybe_emit_notifications(notifications, context, spec, :create)

    action_result = {:ok, result} |> AshJido.Mapper.wrap_result(spec.config)
    {action_result, signal_emission, false}
  end

  defp do_execute_action(%ActionSpec{action_type: :read} = spec, params, _context, ash_opts) do
    {query_opts, action_params} =
      params
      |> AshJido.QueryParams.normalize_keys()
      |> AshJido.QueryParams.split(spec.config)

    query =
      spec.resource
      |> Ash.Query.for_read(spec.action_name, action_params, ash_opts)
      |> maybe_load(spec.config)
      |> AshJido.QueryParams.apply_to_query(query_opts, spec.config)

    result = Ash.read!(query, ash_opts)

    action_result = AshJido.Mapper.wrap_result(result, spec.config)
    {action_result, empty_signal_meta(), false}
  end

  defp do_execute_action(%ActionSpec{action_type: :update} = spec, params, context, ash_opts) do
    primary_key = fetch_primary_key!(params, spec.primary_key, :update)
    update_params = drop_primary_key_params(params, spec.primary_key)

    record =
      spec.resource
      |> fetch_for_write!(primary_key, ash_opts)

    update_result =
      record
      |> Ash.Changeset.for_update(spec.action_name, update_params, ash_opts)
      |> Ash.update!(maybe_add_notification_collection(ash_opts, spec.config, :update))

    {result, notifications} = maybe_extract_result_and_notifications(update_result)

    signal_emission =
      maybe_emit_notifications(notifications, context, spec, :update)

    action_result = {:ok, result} |> AshJido.Mapper.wrap_result(spec.config)
    {action_result, signal_emission, false}
  end

  defp do_execute_action(%ActionSpec{action_type: :destroy} = spec, params, context, ash_opts) do
    primary_key = fetch_primary_key!(params, spec.primary_key, :destroy)
    destroy_params = drop_primary_key_params(params, spec.primary_key)

    record =
      spec.resource
      |> fetch_for_write!(primary_key, ash_opts)

    destroy_result =
      record
      |> Ash.Changeset.for_destroy(spec.action_name, destroy_params, ash_opts)
      |> Ash.destroy!(maybe_add_notification_collection(ash_opts, spec.config, :destroy))

    notifications = maybe_extract_destroy_notifications(destroy_result)

    signal_emission =
      maybe_emit_notifications(notifications, context, spec, :destroy)

    action_result = AshJido.Mapper.wrap_result(:ok, spec.config)
    {action_result, signal_emission, false}
  end

  defp do_execute_action(%ActionSpec{action_type: :action} = spec, params, _context, ash_opts) do
    result =
      spec.resource
      |> Ash.ActionInput.for_action(spec.action_name, params, ash_opts)
      |> Ash.run_action!(ash_opts)

    action_result = {:ok, result} |> AshJido.Mapper.wrap_result(spec.config)
    {action_result, empty_signal_meta(), false}
  end

  defp handle_runtime_exception(error, stacktrace, telemetry_span) do
    signal_meta = empty_signal_meta()

    AshJido.Telemetry.exception(telemetry_span, :error, error, stacktrace, signal_meta)

    jido_error = AshJido.Error.from_ash(error)
    {{:error, jido_error}, signal_meta, true}
  end

  defp telemetry_metadata(spec, ash_opts) do
    %{
      resource: spec.resource,
      ash_action_name: spec.action_name,
      ash_action_type: spec.action_type,
      generated_module: spec.generated_module,
      domain: Keyword.get(ash_opts, :domain),
      tenant: Keyword.get(ash_opts, :tenant),
      actor_present?: not is_nil(Keyword.get(ash_opts, :actor)),
      signaling_enabled?: spec.config.emit_signals?,
      read_load_configured?: not is_nil(spec.config.load)
    }
  end

  defp empty_signal_meta, do: %{failed: [], sent: 0}

  defp fetch_param(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} -> value
      :error -> Map.get(params, to_string(key))
    end
  end

  defp fetch_for_write!(resource, primary_key, ash_opts) do
    Ash.get!(resource, primary_key, Keyword.put(ash_opts, :authorize?, false))
  end

  defp missing_primary_key_message(action_type, primary_key) do
    cond do
      action_type == :update and primary_key == [:id] ->
        "Update actions require an 'id' parameter"

      action_type == :destroy and primary_key == [:id] ->
        "Destroy actions require an 'id' parameter"

      true ->
        action_label = action_type |> Atom.to_string() |> String.capitalize()
        key_list = Enum.map_join(primary_key, ", ", &to_string/1)

        "#{action_label} actions require primary key parameter(s): #{key_list}"
    end
  end

  defp maybe_load(query, config) do
    case config.load do
      nil -> query
      load -> Ash.Query.load(query, load)
    end
  end

  defp maybe_add_notification_collection(ash_opts, config, action_type) do
    if action_type in [:create, :update, :destroy] and config.emit_signals? do
      Keyword.put(ash_opts, :return_notifications?, true)
    else
      ash_opts
    end
  end

  defp maybe_extract_result_and_notifications({result, notifications})
       when is_list(notifications) do
    {result, notifications}
  end

  defp maybe_extract_result_and_notifications(result), do: {result, []}

  defp maybe_extract_destroy_notifications(notifications) when is_list(notifications),
    do: notifications

  defp maybe_extract_destroy_notifications({_result, notifications})
       when is_list(notifications),
       do: notifications

  defp maybe_extract_destroy_notifications(_), do: []

  defp maybe_emit_notifications(notifications, context, spec, action_type) do
    if action_type in [:create, :update, :destroy] and spec.config.emit_signals? do
      AshJido.SignalEmitter.emit_notifications(
        notifications,
        context,
        spec.resource,
        spec.action_name,
        spec.config
      )
    else
      empty_signal_meta()
    end
  end
end
