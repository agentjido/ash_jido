defmodule AshJido.ActorScope do
  @moduledoc """
  Converts an Ash actor to a stable reference before sending a Turn to Jido.

  Set the implementation with `config :ash_jido, :actor_resolver, MyResolver`.
  Use a reference with a binary `:type` and `:id`. Keep actor records and
  credentials out of references. Resolve the actor just before an Ash call.
  """

  @type actor_reference :: %{type: String.t(), id: String.t()}

  @callback reference(actor :: term(), context :: map()) :: {:ok, actor_reference()} | {:error, term()}
  @callback resolve_actor(actor_reference(), context :: map()) :: {:ok, Ash.Resource.record()} | {:error, term()}

  @doc "Builds a Jido caller context with only a portable Ash actor reference and tenant."
  @spec caller_context(term(), term()) :: {:ok, map()} | {:error, atom()}
  def caller_context(actor, tenant) when is_nil(tenant) or is_binary(tenant) do
    scope = if is_nil(tenant), do: %{}, else: %{tenant: tenant}

    with {:ok, scope} <- put_actor_reference(scope, actor) do
      {:ok, %{ash: scope}}
    end
  end

  def caller_context(_actor, _tenant), do: {:error, :invalid_tenant}

  @doc false
  @spec actor(map()) :: {:ok, term()} | {:error, atom()}
  def actor(%{actor_ref: ref} = scope) do
    with false <- Map.has_key?(scope, :actor),
         true <- valid_reference?(ref),
         tenant when is_nil(tenant) or is_binary(tenant) <- Map.get(scope, :tenant),
         {:ok, resolver} <- resolver(:resolve_actor),
         {:ok, %resource{} = actor} <- resolver.resolve_actor(ref, Map.take(scope, [:tenant])),
         true <- Ash.Resource.Info.resource?(resource) do
      {:ok, actor}
    else
      _other -> {:error, :invalid_actor_reference}
    end
  end

  def actor(scope) when is_map(scope), do: {:ok, Map.get(scope, :actor)}
  def actor(_scope), do: {:error, :invalid_actor_reference}

  defp put_actor_reference(scope, nil), do: {:ok, scope}

  defp put_actor_reference(scope, actor) do
    with {:ok, resolver} <- resolver(:reference),
         {:ok, ref} <- resolver.reference(actor, scope),
         true <- valid_reference?(ref) do
      {:ok, Map.put(scope, :actor_ref, ref)}
    else
      _other -> {:error, :invalid_actor_reference}
    end
  end

  defp resolver(callback) do
    module = Application.get_env(:ash_jido, :actor_resolver)

    if is_atom(module) and Code.ensure_loaded?(module) and function_exported?(module, callback, 2),
      do: {:ok, module},
      else: {:error, :actor_resolver_not_configured}
  end

  defp valid_reference?(%{type: type, id: id} = ref)
       when map_size(ref) == 2 and is_binary(type) and is_binary(id),
       do: byte_size(type) > 0 and byte_size(id) > 0

  defp valid_reference?(_ref), do: false
end
