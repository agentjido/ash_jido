defmodule AshJido.State.Transaction do
  @moduledoc false

  alias Ash.Resource.Info
  alias AshJido.Persistence.Adapter
  alias Jido.Persistence.Config

  @type t :: {module(), keyword(), :for_update | nil}

  @doc false
  @spec shared_repo(Config.t(), map()) :: {:ok, t()} | {:error, term()}
  def shared_repo(%Config{store: {Adapter, opts}}, %{resource: resource, touched_resources: touched}) do
    checkpoint = Keyword.fetch!(opts, :resource)
    layer = Info.data_layer(resource)
    resources = Enum.uniq([resource, checkpoint | touched])

    with true <- Keyword.get(opts, :context) in [nil, %{}],
         true <- Enum.all?(resources, &(Info.data_layer(&1) == layer and static_tenancy?(&1))),
         {:ok, repo, transaction_opts, lock} <- backend(layer, resources) do
      {:ok, {repo, transaction_opts, lock}}
    else
      _ -> {:error, :ash_state_requires_shared_transaction}
    end
  end

  def shared_repo(_profile, _resource), do: {:error, :ash_state_requires_ash_persistence}

  @doc false
  @spec run(t(), (-> result)) :: result | {:error, term()} when result: var
  def run({repo, opts, _lock}, fun) do
    case repo.transaction(
           fn ->
             case fun.() do
               {:error, reason} -> repo.rollback({:ash_state_rollback, reason})
               value -> value
             end
           end,
           opts
         ) do
      {:ok, value} -> value
      {:error, {:ash_state_rollback, reason}} -> {:error, reason}
      {:error, _reason} -> {:error, :indeterminate}
    end
  rescue
    _error -> {:error, :indeterminate}
  catch
    :exit, _reason -> {:error, :indeterminate}
  end

  defp backend(AshSqlite.DataLayer, resources) do
    info = AshSqlite.DataLayer.Info

    with {:ok, repo} <- repo(info, resources),
         true <- repo.write_transactions?() do
      {:ok, repo, [mode: :immediate], nil}
    end
  end

  defp backend(AshPostgres.DataLayer, resources) do
    with {:ok, repo} <- repo(AshPostgres.DataLayer.Info, resources) do
      {:ok, repo, [], :for_update}
    end
  end

  defp backend(_layer, _resources), do: :error

  defp repo(info, [resource | _] = resources) do
    write = info.repo(resource, :mutate)

    if is_atom(write) and not is_nil(write) and
         Enum.all?(resources, &(info.repo(&1, :read) == write and info.repo(&1, :mutate) == write)) do
      {:ok, write}
    else
      :error
    end
  end

  defp static_tenancy?(resource), do: Info.multitenancy_strategy(resource) in [nil, :attribute]
end
