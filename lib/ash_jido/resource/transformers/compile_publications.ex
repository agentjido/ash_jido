defmodule AshJido.Resource.Transformers.CompilePublications do
  @moduledoc """
  Compile-time transformer that validates and compiles signal publications.

  Responsibilities:
  - validate `publish` actions exist on the resource
  - expand `publish_all` declarations into concrete action publications
  - normalize publication action names to lists
  - persist compiled publications for runtime lookup
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @doc false
  def transform(dsl_state) do
    resource = Transformer.get_persisted(dsl_state, :module)
    actions = Transformer.get_entities(dsl_state, [:actions])
    action_names = actions |> Enum.map(& &1.name) |> MapSet.new()
    jido_entities = Transformer.get_entities(dsl_state, [:jido])

    explicit_publications =
      jido_entities
      |> Enum.filter(&match?(%AshJido.Publication{}, &1))
      |> Enum.map(fn publication ->
        %AshJido.Publication{} = publication
        actions_list = List.wrap(publication.actions)

        Enum.each(actions_list, fn action_name ->
          unless MapSet.member?(action_names, action_name) do
            raise Spark.Error.DslError,
              module: resource,
              path: [:jido, :publish],
              message: """
              Action #{inspect(action_name)} referenced in `publish` does not exist on #{inspect(resource)}.

              Available actions: #{inspect(MapSet.to_list(action_names))}
              """
          end
        end)

        %AshJido.Publication{
          actions: actions_list,
          signal_type: publication.signal_type,
          include: publication.include,
          metadata: publication.metadata,
          condition: publication.condition
        }
      end)

    expanded_publications =
      jido_entities
      |> Enum.filter(&match?(%AshJido.Resource.PublishAll{}, &1))
      |> Enum.flat_map(fn publish_all ->
        %AshJido.Resource.PublishAll{} = publish_all

        actions
        |> Enum.filter(&(&1.type == publish_all.action_type))
        |> Enum.map(fn action ->
          %AshJido.Publication{
            actions: [action.name],
            signal_type: publish_all.signal_type,
            include: publish_all.include,
            metadata: publish_all.metadata,
            condition: nil
          }
        end)
      end)

    publications = explicit_publications ++ expanded_publications

    {:ok, Transformer.persist(dsl_state, :jido_publications, publications)}
  end

  @doc false
  def before?(_), do: false

  @doc false
  def after?(Ash.Resource.Transformers.ValidateRelationshipAttributes), do: true
  def after?(_), do: false
end
