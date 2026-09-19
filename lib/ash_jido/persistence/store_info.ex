defmodule AshJido.Persistence.StoreInfo do
  @moduledoc "Introspection and validation for an AshJido persistence store resource."

  @required_attributes [:key, :value, :write_token]
  @required_actions %{
    ash_jido_persistence_read: :read,
    ash_jido_persistence_create: :create,
    ash_jido_persistence_update: :update,
    ash_jido_persistence_destroy: :destroy
  }

  @doc "Validates the fixed resource contract required by the persistence adapter."
  @spec validate(module()) :: :ok | {:error, String.t()}
  def validate(resource) when is_atom(resource) do
    with true <- Code.ensure_loaded?(resource) || {:error, "resource is not loaded"},
         true <- Ash.Resource.Info.resource?(resource) || {:error, "resource is not an Ash resource"},
         true <- store?(resource) || {:error, "resource does not declare `jido do persistence_store end`"},
         :ok <- validate_attributes(resource),
         :ok <- validate_actions(resource),
         :ok <- validate_data_layer(resource) do
      :ok
    else
      {:error, _reason} = error -> error
      false -> {:error, "resource is invalid"}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  def validate(_resource), do: {:error, ":resource must be a module"}

  @doc "Returns true when the resource declares the persistence marker."
  @spec store?(module()) :: boolean()
  def store?(resource) do
    Spark.Dsl.Extension.get_persisted(resource, :ash_jido_persistence_store?, false)
  end

  defp validate_attributes(resource) do
    Enum.reduce_while(@required_attributes, :ok, fn name, :ok ->
      case Ash.Resource.Info.attribute(resource, name) do
        %{type: type, allow_nil?: false, public?: false} ->
          if Ash.Type.get_type(type) == Ash.Type.Binary do
            {:cont, :ok}
          else
            {:halt, {:error, "attribute #{inspect(name)} must have type :binary"}}
          end

        _attribute ->
          {:halt, {:error, "attribute #{inspect(name)} must be private, non-null, and :binary"}}
      end
    end)
  end

  defp validate_actions(resource) do
    Enum.reduce_while(@required_actions, :ok, fn {name, type}, :ok ->
      case Ash.Resource.Info.action(resource, name) do
        %{type: ^type, public?: false} -> {:cont, :ok}
        _action -> {:halt, {:error, "private #{type} action #{inspect(name)} is missing"}}
      end
    end)
  end

  defp validate_data_layer(resource) do
    required = [:create, :read, :update_query, :destroy_query, :upsert, {:atomic, :update}]

    case Enum.find(required, &(not Ash.DataLayer.can?(&1, resource))) do
      nil -> :ok
      feature -> {:error, "data layer does not support #{inspect(feature)}"}
    end
  end
end
