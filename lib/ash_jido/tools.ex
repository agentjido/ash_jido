defmodule AshJido.Tools do
  @moduledoc """
  Helpers for exporting generated AshJido actions as Jido tool definitions.
  """

  @spec actions(module()) :: [module()]
  def actions(target) when is_atom(target) do
    cond do
      resource_module?(target) ->
        resource_actions(target)

      domain_module?(target) ->
        domain_actions(target)

      true ->
        []
    end
  end

  @spec tools(module()) :: [map()]
  def tools(target) when is_atom(target) do
    target
    |> actions()
    |> Enum.flat_map(fn action ->
      try do
        [action.to_tool()]
      rescue
        _ -> []
      end
    end)
  end

  defp resource_module?(module) do
    Code.ensure_loaded?(module) and Ash.Resource.Info.resource?(module)
  end

  defp domain_module?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :domain?, 0) and module.domain?()
  end

  defp resource_actions(resource) do
    if Code.ensure_loaded?(resource) and function_exported?(resource, :spark_dsl_config, 0) do
      resource
      |> Kernel.apply(:spark_dsl_config, [])
      |> Spark.Dsl.Extension.get_persisted(:generated_jido_modules, [])
    else
      []
    end
  rescue
    _ -> []
  end

  defp domain_actions(domain) do
    domain
    |> Ash.Domain.Info.resources()
    |> Enum.flat_map(&resource_actions/1)
    |> Enum.uniq()
  rescue
    _ -> []
  end
end
