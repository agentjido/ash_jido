defmodule AshJidoConsumer.PersistenceTest do
  use AshJidoConsumer.DataCase, async: false

  alias AshJido.Persistence.Adapter
  alias AshJidoConsumer.Infrastructure.JidoStore

  defmodule Counter do
    use Jido.Agent, name: "ash_jido_persistence_counter"

    agent do
      schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
    end
  end

  setup do
    {:ok,
     key: "postgres-cas-#{System.unique_integer([:positive, :monotonic])}",
     opts: [resource: JidoStore]}
  end

  test "the AshPostgres resource satisfies the persistence store contract" do
    assert :ok = AshJido.Persistence.StoreInfo.validate(JidoStore)
  end

  test "Jido can save, load, and delete an agent through the Ash adapter", %{
    key: key,
    opts: opts
  } do
    store = {Adapter, opts}
    agent = Counter.new!(id: key, state: %{count: 7})

    assert :ok =
             Jido.Persistence.save_agent(store, agent,
               revision: 1,
               instance: AshJidoConsumer
             )

    assert {:ok, restored} =
             Jido.Persistence.load_agent(store, Counter, key, instance: AshJidoConsumer)

    assert restored.state == %{count: 7}

    assert :ok =
             Jido.Persistence.delete_agent(store, Counter, key, instance: AshJidoConsumer)

    assert {:error, :deleted} =
             Jido.Persistence.load_agent(store, Counter, key, instance: AshJidoConsumer)
  end

  test "token compare-and-swap rejects stale concurrent writers", %{key: key, opts: opts} do
    assert {:error, :not_found} = Adapter.get(key, opts)
    assert :ok = Adapter.compare_and_swap(key, :not_found, "initial", opts)
    assert {:error, :conflict} = Adapter.compare_and_swap(key, :not_found, "duplicate", opts)
    assert {:ok, "initial", token} = Adapter.get(key, opts)

    results =
      1..8
      |> Task.async_stream(
        fn value ->
          Adapter.compare_and_swap(key, {:token, token}, Integer.to_string(value), opts)
        end,
        max_concurrency: 8,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == :ok)) == 1
    assert Enum.count(results, &(&1 == {:error, :conflict})) == 7
  end

  test "same-value writes replace the token and maintenance operations work", %{
    key: key,
    opts: opts
  } do
    assert :ok = Adapter.compare_and_swap(key, :not_found, "same", opts)
    assert {:ok, "same", token} = Adapter.get(key, opts)
    assert :ok = Adapter.compare_and_swap(key, {:token, token}, "same", opts)
    assert {:ok, "same", next_token} = Adapter.get(key, opts)
    refute next_token == token

    assert :ok = Adapter.put(key, "maintenance", opts)
    assert {:ok, "maintenance", _token} = Adapter.get(key, opts)
    assert :ok = Adapter.delete(key, opts)
    assert {:error, :not_found} = Adapter.get(key, opts)
  end
end
