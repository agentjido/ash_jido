defmodule AshJido.Context do
  @moduledoc false

  alias AshJido.ActionDescriptor

  @passthrough_keys [:actor, :tenant, :tracer, :scope, :context, :timeout]

  @doc false
  @spec extract_ash_opts!(map(), ActionDescriptor.t()) :: keyword()
  def extract_ash_opts!(context, %ActionDescriptor{} = descriptor) when is_map(context) do
    ash_context = Map.get(context, :ash, %{})

    unless is_map(ash_context) do
      raise ArgumentError, "AshJido: context.ash must be a map"
    end

    if Map.has_key?(ash_context, :domain) or Map.has_key?(ash_context, "domain") do
      raise ArgumentError, "AshJido: the Ash domain is fixed at compile time"
    end

    if Map.get(ash_context, :authorize?) == false or Map.get(ash_context, "authorize?") == false do
      raise ArgumentError, "AshJido: context cannot disable Ash authorization"
    end

    ash_context = resolve_actor!(ash_context)

    opts =
      Enum.reduce(@passthrough_keys, [domain: descriptor.domain], fn key, opts ->
        case Map.fetch(ash_context, key) do
          {:ok, value} -> Keyword.put(opts, key, value)
          :error -> opts
        end
      end)

    if Map.get(ash_context, :authorize?) == true or Map.get(ash_context, "authorize?") == true do
      Keyword.put(opts, :authorize?, true)
    else
      opts
    end
  end

  defp resolve_actor!(%{actor_ref: _ref} = scope) do
    case AshJido.ActorScope.actor(scope) do
      {:ok, actor} -> Map.put(scope, :actor, actor)
      {:error, :invalid_actor_reference} -> raise ArgumentError, "AshJido: invalid actor reference"
    end
  end

  defp resolve_actor!(scope), do: scope
end
