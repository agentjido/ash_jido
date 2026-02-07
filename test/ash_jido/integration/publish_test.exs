defmodule AshJido.Integration.PublishTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!({Jido.Signal.Bus, name: :ash_jido_test_bus})

    assert {:ok, _subscription_id} =
             Jido.Signal.Bus.subscribe(
               :ash_jido_test_bus,
               "**",
               dispatch: {:pid, target: self()}
             )

    :ok
  end

  test "creating a resource publishes configured signal" do
    actor = %{id: "user-456"}

    AshJido.Test.ReactiveResource
    |> Ash.Changeset.for_create(:create, %{name: "test"})
    |> Ash.create!(actor: actor)

    assert_receive {:signal, %Jido.Signal{type: "test.resource.created"} = signal}, 1000
    assert signal.data.name == "test"
    assert signal_metadata(signal).actor_id == "user-456"
  end

  test "action not configured for publish emits no signal" do
    record =
      AshJido.Test.SelectiveResource
      |> Ash.Changeset.for_create(:create, %{name: "test"})
      |> Ash.create!()

    assert_receive {:signal, %Jido.Signal{type: "test.selective.created"}}, 1000

    record
    |> Ash.Changeset.for_update(:internal_update, %{secret: "changed"})
    |> Ash.update!()

    refute_receive {:signal, _}, 200
  end

  test "conditional publish respects condition function" do
    record =
      AshJido.Test.ReactiveResource
      |> Ash.Changeset.for_create(:create, %{name: "test"})
      |> Ash.create!()

    assert_receive {:signal, %Jido.Signal{type: "test.resource.created"}}, 1000

    updated =
      record
      |> Ash.Changeset.for_update(:update, %{status: :draft})
      |> Ash.update!()

    assert_receive {:signal, %Jido.Signal{type: "test.reactive_resource.update"}}, 1000
    refute_receive {:signal, %Jido.Signal{type: "test.resource.conditional"}}, 200

    updated
    |> Ash.Changeset.for_update(:update, %{status: :published})
    |> Ash.update!()

    types = receive_signal_types(2, [])
    assert "test.resource.conditional" in types
    assert "test.reactive_resource.update" in types
  end

  test "failed Ash action does not publish signal" do
    assert {:error, _error} =
             AshJido.Test.ReactiveResource
             |> Ash.Changeset.for_create(:create, %{})
             |> Ash.create()

    refute_receive {:signal, _}, 200
  end

  test "multi-tenant signals include tenant in metadata" do
    AshJido.Test.ReactiveResource
    |> Ash.Changeset.for_create(:create, %{name: "tenant test"}, tenant: "org_abc")
    |> Ash.create!()

    assert_receive {:signal, %Jido.Signal{type: "test.resource.created"} = signal}, 1000
    assert signal_metadata(signal).tenant == "org_abc"
  end

  defp signal_metadata(signal) do
    Map.get(signal, :jido_metadata) ||
      signal
      |> Map.get(:extensions, %{})
      |> Map.get("jido_metadata", %{})
  end

  defp receive_signal_types(0, types), do: Enum.reverse(types)

  defp receive_signal_types(remaining, types) do
    receive do
      {:signal, %Jido.Signal{type: type}} ->
        receive_signal_types(remaining - 1, [type | types])
    after
      1000 ->
        Enum.reverse(types)
    end
  end
end
