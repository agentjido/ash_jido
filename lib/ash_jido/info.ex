defmodule AshJido.Info do
  @moduledoc """
  Introspection helpers for AshJido DSL configuration.
  """

  use Spark.InfoGenerator,
    extension: AshJido,
    sections: [:jido]

  @doc "Returns the normalized AshJido descriptors compiled for a resource or domain."
  @spec descriptors(module()) :: [AshJido.ActionDescriptor.t()]
  def descriptors(target) when is_atom(target) do
    Spark.Dsl.Extension.get_persisted(target, :ash_jido_descriptors, [])
  end

  @doc "Returns the native Jido Action modules compiled for a resource or domain."
  @spec action_modules(module()) :: [module()]
  def action_modules(target) when is_atom(target) do
    target
    |> descriptors()
    |> Enum.map(& &1.module)
  end

  @doc "Returns the signal bus configured for the resource"
  @spec signal_bus(Ash.Resource.t()) :: {:ok, term()} | :error
  def signal_bus(resource) do
    Spark.Dsl.Extension.fetch_opt(resource, [:jido], :signal_bus)
  end

  @doc "Returns all compiled publication configs for the resource"
  @spec publications(Ash.Resource.t()) :: {:ok, [AshJido.Publication.t()]} | :error
  def publications(resource) do
    Spark.Dsl.Extension.fetch_persisted(resource, :jido_publications)
  end
end
