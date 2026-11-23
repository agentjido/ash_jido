defmodule AshJido.Domain.Transformers.CompileActions do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias AshJido.Domain.Exposure
  alias AshJido.Generator
  alias AshJido.Resource.JidoAction
  alias Spark.Dsl.Transformer

  @impl Spark.Dsl.Transformer
  def transform(dsl_state) do
    references = Transformer.get_entities(dsl_state, [:resources])

    if references == [] do
      {:ok, dsl_state}
    else
      compile_domain(dsl_state, references)
    end
  rescue
    error -> {:error, error}
  end

  defp compile_domain(dsl_state, references) do
    domain = Transformer.get_persisted(dsl_state, :module)
    entities = Transformer.get_entities(dsl_state, [:jido])
    exposures = Enum.filter(entities, &match?(%Exposure{}, &1))
    direct_actions = Enum.filter(entities, &match?(%JidoAction{}, &1))

    interfaces =
      Enum.map(exposures, fn exposure ->
        {resource, interface} = resolve_interface!(domain, references, exposure)
        Generator.interface_descriptor(domain, resource, interface, exposure)
      end)

    actions = Enum.map(direct_actions, &Generator.domain_action_descriptor(domain, &1))

    Generator.compile_actions(dsl_state, interfaces ++ actions, unique_names?: true)
  end

  defp resolve_interface!(domain, references, %Exposure{} = exposure) do
    matches =
      Enum.flat_map(references, fn reference ->
        reference.resource
        |> definitions(reference)
        |> Enum.filter(&(&1.name == exposure.interface))
        |> Enum.map(&{reference.resource, &1})
      end)

    case matches do
      [match] ->
        match

      [] ->
        available =
          references
          |> Enum.flat_map(fn reference -> Enum.map(definitions(reference.resource, reference), & &1.name) end)
          |> Enum.uniq()
          |> Enum.sort()

        raise ArgumentError,
              "AshJido: code interface #{inspect(exposure.interface)} was not found in " <>
                "#{inspect(domain)}; available interfaces: #{inspect(available)}"

      matches ->
        resources = Enum.map(matches, fn {resource, _interface} -> resource end)

        raise ArgumentError,
              "AshJido: code interface #{inspect(exposure.interface)} is ambiguous in " <>
                "#{inspect(domain)}; it is defined for #{inspect(resources)}"
    end
  end

  defp definitions(resource, reference) do
    case reference.definitions do
      [] -> Ash.Resource.Info.interfaces(resource) ++ Ash.Resource.Info.calculation_interfaces(resource)
      definitions -> definitions
    end
  end
end
