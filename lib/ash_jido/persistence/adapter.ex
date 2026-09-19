defmodule AshJido.Persistence.Adapter do
  @moduledoc """
  Jido v3 byte persistence backed by a user-owned Ash resource.

  The resource must use the `persistence_store` AshJido DSL entity. AshJido
  adds private `key`, `value`, and `write_token` attributes and fixed private
  actions. The resource data layer must support atomic query updates.
  """

  @behaviour Jido.Persistence.Adapter

  require Ash.Query

  @read_action :ash_jido_persistence_read
  @create_action :ash_jido_persistence_create
  @update_action :ash_jido_persistence_update
  @destroy_action :ash_jido_persistence_destroy
  @allowed_options [:resource, :domain, :tenant, :context, :timeout, :authorize?]

  @impl true
  def validate_options(opts) do
    with :ok <- validate_keyword(opts),
         {:ok, resource} <- fetch_resource(opts),
         :ok <- AshJido.Persistence.StoreInfo.validate(resource),
         :ok <- validate_domain(resource, Keyword.get(opts, :domain)),
         :ok <- validate_authorization(opts) do
      :ok
    end
  end

  @impl true
  def get(key, opts) when is_binary(key) and is_list(opts) do
    with :ok <- validate_options(opts),
         resource <- Keyword.fetch!(opts, :resource),
         {:ok, record} <-
           Ash.get(resource, key, Keyword.put(operation_opts(resource, opts), :action, @read_action)) do
      {:ok, Map.fetch!(record, :value), Map.fetch!(record, :write_token)}
    else
      {:error, reason} when is_binary(reason) -> {:error, {:rejected, reason}}
      {:error, error} -> normalize_read_error(error)
    end
  rescue
    error -> {:error, {:adapter_failure, Exception.message(error)}}
  catch
    kind, reason -> {:error, {:adapter_failure, {kind, reason}}}
  end

  def get(_key, _opts), do: {:error, {:rejected, :invalid_arguments}}

  @impl true
  def put(key, value, opts)
      when is_binary(key) and is_binary(value) and is_list(opts) do
    with :ok <- validate_options(opts),
         resource <- Keyword.fetch!(opts, :resource),
         {:ok, _record} <-
           Ash.create(
             resource,
             %{key: key, value: value, write_token: write_token()},
             operation_opts(resource, opts) ++
               [
                 action: @create_action,
                 upsert?: true,
                 upsert_fields: [:value, :write_token]
               ]
           ) do
      persistence_event(:put, :ok, resource)
      :ok
    else
      {:error, reason} when is_binary(reason) ->
        {:error, {:rejected, reason}}

      {:error, reason} ->
        resource = Keyword.get(opts, :resource)
        persistence_event(:put, :indeterminate, resource)
        {:error, {:indeterminate, safe_reason(reason)}}
    end
  rescue
    error -> {:error, {:indeterminate, Exception.message(error)}}
  catch
    kind, reason -> {:error, {:indeterminate, {kind, reason}}}
  end

  def put(_key, _value, _opts), do: {:error, {:rejected, :invalid_arguments}}

  @impl true
  def compare_and_swap(key, expected, value, opts)
      when is_binary(key) and is_binary(value) and is_list(opts) do
    with :ok <- validate_expected(expected),
         :ok <- validate_options(opts) do
      do_compare_and_swap(key, expected, value, opts)
    else
      {:error, reason} -> {:error, {:rejected, reason}}
    end
  rescue
    error -> {:error, {:indeterminate, Exception.message(error)}}
  catch
    kind, reason -> {:error, {:indeterminate, {kind, reason}}}
  end

  def compare_and_swap(_key, _expected, _value, _opts),
    do: {:error, {:rejected, :invalid_arguments}}

  @impl true
  def delete(key, opts) when is_binary(key) and is_list(opts) do
    with :ok <- validate_options(opts) do
      resource = Keyword.fetch!(opts, :resource)

      result =
        resource
        |> Ash.Query.filter(key == ^key)
        |> Ash.bulk_destroy(
          @destroy_action,
          %{},
          bulk_opts(resource, opts, return_records?: true)
        )

      case result do
        %Ash.BulkResult{status: status} when status in [:success, :partial_success] -> :ok
        %Ash.BulkResult{} = result -> {:error, {:indeterminate, bulk_reason(result)}}
      end
    else
      {:error, reason} -> {:error, {:rejected, reason}}
    end
  rescue
    error -> {:error, {:indeterminate, Exception.message(error)}}
  catch
    kind, reason -> {:error, {:indeterminate, {kind, reason}}}
  end

  def delete(_key, _opts), do: {:error, {:rejected, :invalid_arguments}}

  defp do_compare_and_swap(key, :not_found, value, opts) do
    resource = Keyword.fetch!(opts, :resource)

    case Ash.create(
           resource,
           %{key: key, value: value, write_token: write_token()},
           Keyword.put(operation_opts(resource, opts), :action, @create_action)
         ) do
      {:ok, _record} ->
        persistence_event(:compare_and_swap, :ok, resource)
        :ok

      {:error, error} ->
        if conflict_error?(error) do
          persistence_event(:compare_and_swap, :conflict, resource)
          {:error, :conflict}
        else
          persistence_event(:compare_and_swap, :indeterminate, resource)
          {:error, {:indeterminate, safe_reason(error)}}
        end
    end
  end

  defp do_compare_and_swap(key, expected, value, opts) do
    resource = Keyword.fetch!(opts, :resource)

    result =
      expected_query(resource, key, expected)
      |> Ash.bulk_update(
        @update_action,
        %{value: value, write_token: write_token()},
        bulk_opts(resource, opts, return_records?: true)
      )

    case result do
      %Ash.BulkResult{status: :success, records: [_record]} ->
        persistence_event(:compare_and_swap, :ok, resource)
        :ok

      %Ash.BulkResult{status: :success, records: []} ->
        persistence_event(:compare_and_swap, :conflict, resource)
        {:error, :conflict}

      %Ash.BulkResult{} = result ->
        persistence_event(:compare_and_swap, :indeterminate, resource)
        {:error, {:indeterminate, bulk_reason(result)}}
    end
  end

  defp expected_query(resource, key, {:token, token}),
    do: Ash.Query.filter(resource, key == ^key and write_token == ^token)

  defp expected_query(resource, key, bytes) when is_binary(bytes),
    do: Ash.Query.filter(resource, key == ^key and value == ^bytes)

  defp operation_opts(resource, opts) do
    [
      domain: Keyword.get(opts, :domain) || Ash.Resource.Info.domain(resource),
      tenant: Keyword.get(opts, :tenant),
      context: Keyword.get(opts, :context),
      timeout: Keyword.get(opts, :timeout),
      authorize?: false
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp bulk_opts(resource, opts, extra) do
    Keyword.merge(
      operation_opts(resource, opts),
      [strategy: [:atomic], return_errors?: true, stop_on_error?: true] ++ extra
    )
  end

  defp validate_keyword(opts) do
    cond do
      not Keyword.keyword?(opts) -> {:error, "options must be a keyword list"}
      Enum.any?(Keyword.keys(opts), &(&1 not in @allowed_options)) -> {:error, "options contain an unsupported key"}
      true -> :ok
    end
  end

  defp fetch_resource(opts) do
    case Keyword.fetch(opts, :resource) do
      {:ok, resource} when is_atom(resource) -> {:ok, resource}
      _other -> {:error, "requires a :resource module"}
    end
  end

  defp validate_domain(resource, nil) do
    if is_atom(Ash.Resource.Info.domain(resource)), do: :ok, else: {:error, "requires a fixed :domain"}
  end

  defp validate_domain(_resource, domain) when is_atom(domain), do: :ok
  defp validate_domain(_resource, _domain), do: {:error, ":domain must be a module"}

  defp validate_authorization(opts) do
    case Keyword.get(opts, :authorize?, false) do
      false -> :ok
      _other -> {:error, ":authorize? is fixed to false for the infrastructure store"}
    end
  end

  defp validate_expected(:not_found), do: :ok
  defp validate_expected(expected) when is_binary(expected), do: :ok
  defp validate_expected({:token, token}) when is_binary(token) and byte_size(token) > 0, do: :ok
  defp validate_expected(_expected), do: {:error, :invalid_expected_value}

  defp normalize_read_error(error) do
    if not_found_error?(error), do: {:error, :not_found}, else: {:error, safe_reason(error)}
  end

  defp not_found_error?(error), do: error_modules(error) |> Enum.any?(&String.contains?(&1, "NotFound"))

  defp conflict_error?(error) do
    conflict_message?(error) or
      Enum.any?(error_modules(error), fn name ->
        String.contains?(name, "AlreadyExists") or String.contains?(name, "Unique") or
          String.contains?(name, "Conflict")
      end)
  end

  defp conflict_message?(%{errors: errors}) when is_list(errors),
    do: Enum.any?(errors, &conflict_message?/1)

  defp conflict_message?(%{message: message}) when is_binary(message),
    do: String.contains?(message, ["already been taken", "unique constraint", "conflict"])

  defp conflict_message?(_error), do: false

  defp error_modules(%{errors: errors}) when is_list(errors),
    do: Enum.flat_map(errors, &error_modules/1)

  defp error_modules(%{__struct__: module}), do: [inspect(module)]
  defp error_modules(_error), do: []

  defp bulk_reason(%Ash.BulkResult{status: status, error_count: count}),
    do: %{status: status, error_count: count}

  defp safe_reason(_error), do: :storage_operation_failed

  defp write_token, do: :crypto.strong_rand_bytes(16)

  defp persistence_event(operation, result, resource) do
    :telemetry.execute(
      [:ash_jido, :persistence, :result],
      %{count: 1},
      %{operation: operation, result: result, resource: resource}
    )
  end
end
