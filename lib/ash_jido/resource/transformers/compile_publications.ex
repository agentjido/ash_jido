defmodule AshJido.Resource.Transformers.CompilePublications do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias AshJido.Publication
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
    actions = Transformer.get_entities(dsl_state, [:actions])
    action_names = MapSet.new(actions, & &1.name)

    publications =
      dsl_state
      |> Transformer.get_entities([:jido])
      |> Enum.filter(&match?(%Publication{}, &1))
      |> Enum.map(&validate_publication!(&1, resource, action_names, dsl_state))

    {:ok, Transformer.persist(dsl_state, :jido_publications, publications)}
  end

  defp validate_publication!(publication, resource, action_names, dsl_state) do
    actions = List.wrap(publication.actions)

    Enum.each(actions, fn action ->
      unless MapSet.member?(action_names, action) do
        raise ArgumentError,
              "AshJido: signal publication action #{inspect(action)} does not exist on #{inspect(resource)}"
      end
    end)

    unless is_binary(publication.signal_type) and publication.signal_type != "" do
      raise ArgumentError,
            "AshJido: signal publication for #{inspect(resource)} requires an explicit signal type"
    end

    validate_include!(publication.include, resource, dsl_state)
    %{publication | actions: actions}
  end

  defp validate_include!(fields, resource, dsl_state) when is_list(fields) do
    attributes =
      dsl_state
      |> Transformer.get_entities([:attributes])
      |> Map.new(&{&1.name, &1})

    Enum.each(fields, fn field ->
      case Map.get(attributes, field) do
        %{public?: true, sensitive?: false} -> :ok
        _other -> raise ArgumentError, "AshJido: signal field #{inspect(field)} is not public on #{inspect(resource)}"
      end
    end)
  end

  defp validate_include!(_mode, _resource, _dsl_state), do: :ok

  @impl Spark.Dsl.Transformer
  def after?(Ash.Resource.Transformers.ValidateRelationshipAttributes), do: true
  def after?(_transformer), do: false
end
