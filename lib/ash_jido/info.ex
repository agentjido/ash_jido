defmodule AshJido.Info do
  @moduledoc """
  Introspection helpers for AshJido DSL configuration.
  """

  use Spark.InfoGenerator,
    extension: AshJido,
    sections: [:jido]

  @doc "Returns the signal bus configured for the resource"
  @spec signal_bus(Ash.Resource.t()) :: {:ok, term()} | :error
  def signal_bus(resource) do
    Spark.Dsl.Extension.fetch_opt(resource, [:jido], :signal_bus)
  end

  @doc "Returns the signal prefix configured for the resource"
  @spec signal_prefix(Ash.Resource.t()) :: {:ok, String.t()} | :error
  def signal_prefix(resource) do
    Spark.Dsl.Extension.fetch_opt(resource, [:jido], :signal_prefix)
  end

  @doc "Returns all compiled publication configs for the resource"
  @spec publications(Ash.Resource.t()) :: {:ok, [AshJido.Publication.t()]} | :error
  def publications(resource) do
    Spark.Dsl.Extension.fetch_persisted(resource, :jido_publications)
  end
end
