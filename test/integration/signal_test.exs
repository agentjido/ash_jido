defmodule AshJido.V3SignalTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!({Jido.Signal.Bus, name: :ash_jido_test_bus})

    assert {:ok, _subscription} =
             Jido.Signal.Bus.subscribe(:ash_jido_test_bus, "**", target: self())

    :ok
  end

  test "one generated Action produces one notifier signal with safe data" do
    assert {:ok, %{result: result}} =
             Jido.Exec.run(
               AshJido.Test.ReactiveResource.Jido.Create,
               %{name: "Signal"},
               %{ash: %{actor: %{id: "actor-1"}}}
             )

    assert result.name == "Signal"

    assert_receive {:signal, %Jido.Signal{type: "test.resource.created"} = signal}, 1_000
    assert signal.data.name == "Signal"
    refute Map.has_key?(signal.data, :secret)
    assert get_in(signal.data, [:ash_jido, :actor_id]) == "actor-1"
    refute_receive {:signal, _signal}, 100
  end

  test "changes-only publications remove private fields" do
    record =
      AshJido.Test.ReactiveResource
      |> Ash.Changeset.for_create(:create, %{name: "Private signal"})
      |> Ash.create!()

    assert_receive {:signal, %Jido.Signal{type: "test.resource.created"}}, 1_000

    record
    |> Ash.Changeset.for_update(:internal_update, %{secret: "hidden"})
    |> Ash.update!()

    assert_receive {:signal, %Jido.Signal{type: "test.resource.internal_updated", data: %{}}},
                   1_000
  end
end
