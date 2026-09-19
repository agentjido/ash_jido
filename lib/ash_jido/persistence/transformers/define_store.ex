defmodule AshJido.Persistence.Transformers.DefineStore do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias Ash.Resource.Builder
  alias AshJido.Persistence.Store
  alias Spark.Dsl.Transformer

  @read_action :ash_jido_persistence_read
  @create_action :ash_jido_persistence_create
  @update_action :ash_jido_persistence_update
  @destroy_action :ash_jido_persistence_destroy

  @impl Spark.Dsl.Transformer
  def transform(dsl_state) do
    entities = Transformer.get_entities(dsl_state, [:jido])

    if Enum.any?(entities, &match?(%Store{}, &1)) and
         Transformer.get_entities(dsl_state, [:resources]) == [] do
      define_store(dsl_state)
    else
      {:ok, dsl_state}
    end
  end

  defp define_store(dsl_state) do
    with {:ok, dsl_state} <- add_attribute(dsl_state, :key, primary_key?: true),
         {:ok, dsl_state} <- add_attribute(dsl_state, :value),
         {:ok, dsl_state} <- add_attribute(dsl_state, :write_token),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :read, @read_action,
             public?: false,
             primary?: true
           ),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :create, @create_action,
             public?: false,
             accept: [:key, :value, :write_token]
           ),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :update, @update_action,
             public?: false,
             accept: [:value, :write_token],
             require_atomic?: true
           ),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :destroy, @destroy_action, public?: false) do
      {:ok, Transformer.persist(dsl_state, :ash_jido_persistence_store?, true)}
    end
  end

  defp add_attribute(dsl_state, name, extra_opts \\ []) do
    opts = Keyword.merge([allow_nil?: false, public?: false, writable?: true], extra_opts)
    Builder.add_new_attribute(dsl_state, name, :binary, opts)
  end

  @impl Spark.Dsl.Transformer
  def before?(Ash.Resource.Transformers.CachePrimaryKey), do: true
  def before?(_transformer), do: false
end
