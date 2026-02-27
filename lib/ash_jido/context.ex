defmodule AshJido.Context do
  @moduledoc false

  @optional_passthrough_keys [:authorize?, :tracer, :scope, :context, :timeout]

  @spec extract_ash_opts!(map(), module(), atom()) :: keyword()
  def extract_ash_opts!(context, resource, action_name) when is_map(context) do
    domain = require_domain!(context, resource, action_name)

    context
    |> base_opts(domain)
    |> maybe_add_optional_passthroughs(context)
  end

  defp base_opts(context, domain) do
    [
      actor: Map.get(context, :actor),
      tenant: Map.get(context, :tenant),
      domain: domain
    ]
  end

  defp maybe_add_optional_passthroughs(ash_opts, context) do
    Enum.reduce(@optional_passthrough_keys, ash_opts, fn key, opts ->
      if Map.has_key?(context, key) do
        Keyword.put(opts, key, Map.get(context, key))
      else
        opts
      end
    end)
  end

  defp require_domain!(context, resource, action_name) do
    case Map.get(context, :domain) do
      nil ->
        raise ArgumentError,
              "AshJido: :domain must be provided in context for #{inspect(resource)}.#{action_name}"

      domain ->
        domain
    end
  end
end
