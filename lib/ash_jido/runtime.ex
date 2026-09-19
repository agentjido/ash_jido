defmodule AshJido.Runtime do
  @moduledoc false

  alias AshJido.ActionDescriptor

  @doc false
  @spec run(ActionDescriptor.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def run(%ActionDescriptor{} = descriptor, params, context)
      when is_map(params) and is_map(context) do
    ash_opts =
      context
      |> AshJido.Context.extract_ash_opts!(descriptor)
      |> merge_default_options(descriptor.config)

    with {:ok, params} <- transform_custom_inputs(params, descriptor) do
      execute(descriptor, params, ash_opts)
    end
  rescue
    error -> {:error, AshJido.Error.from_ash(error)}
  catch
    kind, reason -> {:error, AshJido.Error.internal(kind, reason)}
  end

  @doc false
  @spec fetch_primary_key!(map(), [atom()], atom()) :: term()
  def fetch_primary_key!(params, primary_key, action_type) do
    case fetch_identity(params, primary_key, action_type) do
      {:ok, identity} -> identity
      {:error, message} -> raise ArgumentError, message
    end
  end

  @doc false
  @spec drop_primary_key_params(map(), [atom()]) :: map()
  def drop_primary_key_params(params, primary_key) do
    Enum.reduce(primary_key, params, fn key, result ->
      Map.drop(result, [key, to_string(key)])
    end)
  end

  defp execute(%ActionDescriptor{action_type: :create} = descriptor, params, ash_opts) do
    descriptor.resource
    |> Ash.Changeset.for_create(descriptor.ash_action, params, ash_opts)
    |> maybe_select_changeset(descriptor.select)
    |> Ash.create(ash_opts)
    |> load_and_envelope(descriptor, ash_opts)
  end

  defp execute(%ActionDescriptor{action_type: :read} = descriptor, params, ash_opts) do
    {query_params, action_params} =
      params
      |> AshJido.QueryParams.normalize_keys()
      |> AshJido.QueryParams.split(descriptor.config)

    {identity_filter, action_params} = split_identity_filter(action_params, descriptor)

    query =
      descriptor.resource
      |> Ash.Query.for_read(descriptor.ash_action, action_params, ash_opts)
      |> maybe_filter_identity(identity_filter)
      |> maybe_select_query(descriptor.select)
      |> maybe_load_query(descriptor.load)
      |> AshJido.QueryParams.apply_to_query(query_params, descriptor.config)

    result =
      case descriptor.result_cardinality do
        :one -> Ash.read_one(query, Keyword.put(ash_opts, :not_found_error?, not_found_error?(descriptor)))
        _other -> Ash.read(query, ash_opts)
      end

    result_envelope(result)
  end

  defp execute(%ActionDescriptor{action_type: :update} = descriptor, params, ash_opts) do
    with {:ok, identity} <- fetch_identity(params, descriptor.identity, :update),
         {:ok, record} <- Ash.get(descriptor.resource, identity, ash_opts),
         update_params <- drop_primary_key_params(params, descriptor.identity),
         changeset <- Ash.Changeset.for_update(record, descriptor.ash_action, update_params, ash_opts),
         changeset <- maybe_select_changeset(changeset, descriptor.select),
         {:ok, result} <- Ash.update(changeset, ash_opts) do
      load_and_envelope({:ok, result}, descriptor, ash_opts)
    else
      {:error, error} -> {:error, AshJido.Error.from_ash(error)}
    end
  end

  defp execute(%ActionDescriptor{action_type: :destroy} = descriptor, params, ash_opts) do
    with {:ok, identity} <- fetch_identity(params, descriptor.identity, :destroy),
         {:ok, record} <- Ash.get(descriptor.resource, identity, ash_opts),
         destroy_params <- drop_primary_key_params(params, descriptor.identity),
         changeset <- Ash.Changeset.for_destroy(record, descriptor.ash_action, destroy_params, ash_opts),
         result <- Ash.destroy(changeset, ash_opts),
         :ok <- normalize_destroy_result(result) do
      {:ok,
       %{
         result: %{destroyed?: true, identity: identity_map(identity, descriptor.identity)},
         page: nil,
         metadata: nil
       }}
    else
      {:error, error} -> {:error, AshJido.Error.from_ash(error)}
    end
  end

  defp execute(%ActionDescriptor{action_type: :action} = descriptor, params, ash_opts) do
    descriptor.resource
    |> Ash.ActionInput.for_action(descriptor.ash_action, params, ash_opts)
    |> Ash.run_action(ash_opts)
    |> result_envelope()
  end

  defp execute(%ActionDescriptor{action_type: :calculation} = descriptor, params, ash_opts) do
    argument_names = config_value(descriptor.config, :calculation_arguments, [])
    reference_names = config_value(descriptor.config, :calculation_refs, [])
    {arguments, params} = take_fields(params, argument_names)
    {refs, _params} = take_fields(params, reference_names)

    options =
      ash_opts
      |> Keyword.take([:domain, :actor, :tenant, :scope, :context, :tracer, :authorize?])
      |> Keyword.merge(args: arguments, refs: refs)

    descriptor.resource
    |> Ash.calculate(descriptor.ash_action, options)
    |> result_envelope()
  end

  defp transform_custom_inputs(params, descriptor) do
    custom_inputs = config_value(descriptor.config, :custom_inputs, []) || []

    case Ash.CodeInterface.handle_custom_inputs(params, custom_inputs, descriptor.resource) do
      {params, []} -> {:ok, params}
      {_params, errors} -> {:error, AshJido.Error.from_ash(Ash.Error.to_error_class(errors))}
    end
  end

  defp merge_default_options(ash_opts, config) do
    defaults = config_value(config, :default_options, []) || []
    Keyword.merge(defaults, ash_opts)
  end

  defp split_identity_filter(params, %{source: {:code_interface, _domain, _name}} = descriptor) do
    keys = config_value(descriptor.config, :get_by, []) || []
    {filter, params} = take_fields(params, keys)
    {filter, params}
  end

  defp split_identity_filter(params, _descriptor), do: {%{}, params}

  defp take_fields(params, keys) do
    Enum.reduce(keys, {%{}, params}, fn key, {values, remaining} ->
      case fetch_param(remaining, key) do
        nil -> {values, remaining}
        value -> {Map.put(values, key, value), Map.drop(remaining, [key, to_string(key)])}
      end
    end)
  end

  defp maybe_filter_identity(query, filter) when map_size(filter) == 0, do: query
  defp maybe_filter_identity(query, filter), do: Ash.Query.filter_input(query, filter)

  defp maybe_select_query(query, nil), do: query
  defp maybe_select_query(query, fields), do: Ash.Query.select(query, fields)

  defp maybe_load_query(query, nil), do: query
  defp maybe_load_query(query, load), do: Ash.Query.load(query, load)

  defp maybe_select_changeset(changeset, nil), do: changeset
  defp maybe_select_changeset(changeset, fields), do: Ash.Changeset.select(changeset, fields)

  defp load_and_envelope({:ok, result}, %{load: nil}, _ash_opts),
    do: {:ok, AshJido.Serializer.envelope(result)}

  defp load_and_envelope({:ok, result}, descriptor, ash_opts) do
    case Ash.load(result, descriptor.load, ash_opts) do
      {:ok, loaded} -> {:ok, AshJido.Serializer.envelope(loaded)}
      {:error, error} -> {:error, AshJido.Error.from_ash(error)}
    end
  end

  defp load_and_envelope({:error, error}, _descriptor, _ash_opts),
    do: {:error, AshJido.Error.from_ash(error)}

  defp result_envelope({:ok, result}), do: {:ok, AshJido.Serializer.envelope(result)}
  defp result_envelope({:error, error}), do: {:error, AshJido.Error.from_ash(error)}

  defp normalize_destroy_result(:ok), do: :ok
  defp normalize_destroy_result({:ok, _record}), do: :ok
  defp normalize_destroy_result({:error, error}), do: {:error, error}

  defp fetch_identity(_params, [], action_type),
    do: {:error, "#{action_type} action has no configured identity"}

  defp fetch_identity(params, identity_fields, action_type) do
    values = Map.new(identity_fields, &{&1, fetch_param(params, &1)})
    missing = for {key, nil} <- values, do: key

    if missing == [] do
      case identity_fields do
        [key] when key in [:id] -> {:ok, Map.fetch!(values, key)}
        _keys -> {:ok, values}
      end
    else
      {:error,
       "#{action_type |> Atom.to_string() |> String.capitalize()} actions require identity fields: " <>
         Enum.map_join(missing, ", ", &to_string/1)}
    end
  end

  defp identity_map(identity, [key]) when not is_map(identity), do: %{key => identity}
  defp identity_map(identity, _keys) when is_map(identity), do: identity

  defp fetch_param(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} -> value
      :error -> Map.get(params, to_string(key))
    end
  end

  defp not_found_error?(descriptor) do
    case config_value(descriptor.config, :not_found_error?) do
      nil -> true
      value -> value
    end
  end

  defp config_value(config, key, default \\ nil), do: Map.get(config, key, default)
end
