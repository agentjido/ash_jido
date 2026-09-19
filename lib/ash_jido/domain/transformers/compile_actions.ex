defmodule AshJido.Domain.Transformers.CompileActions do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias AshJido.Domain.Exposure
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

    resolved = Enum.map(exposures, &resolve_interface!(domain, references, &1))
    validate_unique_declarations!(domain, resolved, direct_actions)

    modules =
      Enum.map(resolved, fn
        {resource, %Ash.Resource.Interface{} = interface, exposure} ->
          AshJido.Generator.generate_interface_action_module(domain, resource, interface, exposure)

        {resource, %Ash.Resource.CalculationInterface{} = interface, exposure} ->
          AshJido.Generator.generate_calculation_action_module(domain, resource, interface, exposure)
      end) ++
        Enum.map(direct_actions, &AshJido.Generator.generate_domain_action_module(domain, &1))

    descriptors = Enum.map(modules, & &1.__ash_jido__())

    {:ok,
     dsl_state
     |> Transformer.persist(:generated_jido_modules, modules)
     |> Transformer.persist(:ash_jido_descriptors, descriptors)}
  end

  defp resolve_interface!(domain, references, %Exposure{} = exposure) do
    matches =
      Enum.flat_map(references, fn reference ->
        reference.resource
        |> definitions(reference)
        |> Enum.filter(&(&1.name == exposure.interface))
        |> Enum.map(&{reference.resource, &1, exposure})
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
        resources = Enum.map(matches, fn {resource, _interface, _exposure} -> resource end)

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

  defp validate_unique_declarations!(domain, resolved, direct_actions) do
    names =
      Enum.map(resolved, fn {_resource, interface, exposure} ->
        exposure.name || Atom.to_string(interface.name)
      end) ++
        Enum.map(direct_actions, fn declaration ->
          declaration.name || Atom.to_string(declaration.action)
        end)

    case duplicate(names) do
      nil -> :ok
      name -> raise ArgumentError, "AshJido: duplicate Jido Action name #{inspect(name)} in #{inspect(domain)}"
    end

    modules =
      Enum.map(resolved, fn {_resource, interface, exposure} ->
        exposure.module_name || Module.concat([domain, "Jido", camelize(interface.name)])
      end) ++
        Enum.map(direct_actions, fn declaration ->
          declaration.module_name || Module.concat([domain, "Jido", camelize(declaration.action)])
        end)

    case duplicate(modules) do
      nil -> :ok
      module -> raise ArgumentError, "AshJido: duplicate generated module #{inspect(module)} in #{inspect(domain)}"
    end
  end

  defp duplicate(values) do
    values
    |> Enum.frequencies()
    |> Enum.find_value(fn
      {value, count} when count > 1 -> value
      _entry -> nil
    end)
  end

  defp camelize(value), do: value |> to_string() |> Macro.camelize()
end
