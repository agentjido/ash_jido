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

    actions =
      dsl_state
      |> Transformer.get_entities([:jido])
      |> Enum.filter(&match?(%JidoAction{}, &1))

    validate_unique_modules!(resource, actions, dsl_state)

    modules = Enum.map(actions, &Generator.generate_jido_action_module(resource, &1, dsl_state))
    descriptors = Enum.map(modules, & &1.__ash_jido__())

    {:ok,
     dsl_state
     |> Transformer.persist(:generated_jido_modules, modules)
     |> Transformer.persist(:ash_jido_descriptors, descriptors)}
  end

  defp validate_unique_modules!(resource, actions, dsl_state) do
    duplicate =
      actions
      |> Enum.map(&Generator.target_module_name(resource, &1, dsl_state))
      |> Enum.frequencies()
      |> Enum.find_value(fn
        {module, count} when count > 1 -> module
        _entry -> nil
      end)

    if duplicate do
      raise ArgumentError,
            "AshJido: multiple declarations on #{inspect(resource)} generate #{inspect(duplicate)}"
    end
  end

  @impl Spark.Dsl.Transformer
  def after?(Ash.Resource.Transformers.ValidateRelationshipAttributes), do: true
  def after?(_transformer), do: false
end
