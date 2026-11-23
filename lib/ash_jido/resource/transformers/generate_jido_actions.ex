defmodule AshJido.Resource.Transformers.GenerateJidoActions do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias AshJido.Generator
  alias AshJido.Resource.JidoAction
  alias Spark.Dsl.Transformer

  @impl Spark.Dsl.Transformer
  def transform(dsl_state) do
    if Transformer.get_entities(dsl_state, [:resources]) == [] do
      compile_resource(dsl_state)
    else
      {:ok, dsl_state}
    end
  rescue
    error -> {:error, error}
  end

  defp compile_resource(dsl_state) do
    resource = Transformer.get_persisted(dsl_state, :module)

    descriptors =
      dsl_state
      |> Transformer.get_entities([:jido])
      |> Enum.filter(&match?(%JidoAction{}, &1))
      |> Enum.map(&Generator.resource_action_descriptor(resource, &1, dsl_state))

    Generator.compile_actions(dsl_state, descriptors, unique_names?: false)
  end

  @impl Spark.Dsl.Transformer
  def after?(Ash.Resource.Transformers.SetPrimaryActions), do: true
  def after?(_transformer), do: false
end
