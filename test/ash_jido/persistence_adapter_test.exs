defmodule AshJido.PersistenceAdapterTest do
  use ExUnit.Case, async: false

  alias AshJido.Persistence.Adapter
  alias AshJido.Test.PersistenceStore

  setup do
    key = "persistence-#{System.unique_integer([:positive, :monotonic])}"
    {:ok, key: key, opts: [resource: PersistenceStore]}
  end

  test "the generated store contract is private and valid" do
    assert :ok = AshJido.Persistence.StoreInfo.validate(PersistenceStore)
    assert AshJido.Persistence.StoreInfo.store?(PersistenceStore)

    for field <- [:key, :value, :write_token] do
      assert %{public?: false, allow_nil?: false} = Ash.Resource.Info.attribute(PersistenceStore, field)
    end
  end

  test "missing insert and token compare-and-swap", %{key: key, opts: opts} do
    assert {:error, :not_found} = Adapter.get(key, opts)
    assert :ok = Adapter.compare_and_swap(key, :not_found, "one", opts)
    assert {:error, :conflict} = Adapter.compare_and_swap(key, :not_found, "other", opts)

    assert {:ok, "one", token} = Adapter.get(key, opts)
    assert :ok = Adapter.compare_and_swap(key, {:token, token}, "two", opts)
    assert {:error, :conflict} = Adapter.compare_and_swap(key, {:token, token}, "stale", opts)
    assert {:ok, "two", new_token} = Adapter.get(key, opts)
    refute new_token == token
  end

  test "same-value writes still replace the token", %{key: key, opts: opts} do
    assert :ok = Adapter.compare_and_swap(key, :not_found, "same", opts)
    assert {:ok, "same", token} = Adapter.get(key, opts)
    assert :ok = Adapter.compare_and_swap(key, {:token, token}, "same", opts)
    assert {:ok, "same", next_token} = Adapter.get(key, opts)
    refute next_token == token
  end

  test "byte comparison, maintenance put, and delete", %{key: key, opts: opts} do
    assert :ok = Adapter.compare_and_swap(key, :not_found, "one", opts)
    assert :ok = Adapter.compare_and_swap(key, "one", "two", opts)
    assert {:error, :conflict} = Adapter.compare_and_swap(key, "one", "three", opts)
    assert :ok = Adapter.put(key, "maintenance", opts)
    assert {:ok, "maintenance", _token} = Adapter.get(key, opts)
    assert :ok = Adapter.delete(key, opts)
    assert {:error, :not_found} = Adapter.get(key, opts)
  end

  test "a stale token cannot replace a later write", %{key: key, opts: opts} do
    assert :ok = Adapter.compare_and_swap(key, :not_found, "initial", opts)
    assert {:ok, "initial", token} = Adapter.get(key, opts)
    assert :ok = Adapter.compare_and_swap(key, {:token, token}, "winner", opts)
    assert {:error, :conflict} = Adapter.compare_and_swap(key, {:token, token}, "stale", opts)
  end

  test "adapter options cannot enable authorization", %{opts: opts} do
    assert {:error, message} = Adapter.validate_options(Keyword.put(opts, :authorize?, true))
    assert message =~ "fixed to false"

    assert {:error, {:rejected, rejected}} =
             Adapter.put("key", "value", Keyword.put(opts, :authorize?, true))

    assert rejected =~ "fixed to false"

    invalid_opts = Keyword.put(opts, :authorize?, true)

    assert {:error, {:rejected, _reason}} = Adapter.get("key", invalid_opts)
    assert {:error, {:rejected, _reason}} = Adapter.delete("key", invalid_opts)

    assert {:error, {:rejected, _reason}} =
             Adapter.compare_and_swap("key", :not_found, "value", invalid_opts)
  end

  test "adapter rejects invalid arguments and options", %{opts: opts} do
    assert {:error, ":resource must be a module"} = AshJido.Persistence.StoreInfo.validate("store")
    assert {:error, "resource is not an Ash resource"} = AshJido.Persistence.StoreInfo.validate(String)
    refute AshJido.Persistence.StoreInfo.store?(AshJido.Test.User)

    assert {:error, "options must be a keyword list"} = Adapter.validate_options(%{})
    assert {:error, "requires a :resource module"} = Adapter.validate_options([])
    assert {:error, "options contain an unsupported key"} = Adapter.validate_options(opts ++ [unknown: true])
    assert {:error, ":domain must be a module"} = Adapter.validate_options(opts ++ [domain: "bad"])
    assert :ok = Adapter.validate_options(opts ++ [domain: AshJido.Test.PersistenceDomain])

    assert {:error, {:rejected, :invalid_arguments}} = Adapter.get(:key, opts)
    assert {:error, {:rejected, :invalid_arguments}} = Adapter.put("key", :value, opts)
    assert {:error, {:rejected, :invalid_arguments}} = Adapter.delete(:key, opts)

    assert {:error, {:rejected, :invalid_arguments}} =
             Adapter.compare_and_swap(:key, :not_found, "value", opts)

    assert {:error, {:rejected, :invalid_expected_value}} =
             Adapter.compare_and_swap("key", {:token, ""}, "value", opts)
  end
end
