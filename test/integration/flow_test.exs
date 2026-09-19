defmodule AshJido.V3FlowTest do
  use ExUnit.Case, async: false

  alias Jido.Flow.Builder

  test "generated Actions compose in a sequential Jido Flow" do
    email = "flow-#{System.unique_integer([:positive])}@example.com"
    flow = create_and_fetch_flow()

    assert {:ok, %{result: %{email: ^email}}} =
             Jido.Exec.run(flow, %{name: "Flow User", email: email}, %{})
  end

  test "independent generated Actions compose in a parallel Jido Flow" do
    flow = parallel_calculations_flow()

    assert {:ok, %{left: 6, right: 10}} =
             Jido.Exec.run(flow, %{left: 3, right: 5}, %{}, max_concurrency: 2)
  end

  test "AshJido does not add a second Flow runtime" do
    refute Code.ensure_loaded?(AshJido.Flow)
  end

  defp create_and_fetch_flow do
    Builder.new(name: "ash_jido_create_and_fetch")
    |> Builder.step("create", AshJido.Test.Domain.Jido.RegisterUser, %{
      name: Builder.input(:name),
      email: Builder.input(:email)
    })
    |> Builder.step("fetch", AshJido.Test.Domain.Jido.GetUser, %{
      id: Builder.result("create", [:result, :id])
    })
    |> Builder.output(Builder.result("fetch"))
    |> then(fn builder ->
      assert {:ok, flow} = Builder.build(builder)
      flow
    end)
  end

  defp parallel_calculations_flow do
    Builder.new(name: "ash_jido_parallel_calculations")
    |> Builder.step("left", AshJido.Test.Domain.Jido.DoubleValue, %{
      value: Builder.input(:left)
    })
    |> Builder.step("right", AshJido.Test.Domain.Jido.DoubleValue, %{
      value: Builder.input(:right)
    })
    |> Builder.output(%{
      left: Builder.result("left", [:result]),
      right: Builder.result("right", [:result])
    })
    |> then(fn builder ->
      assert {:ok, flow} = Builder.build(builder)
      flow
    end)
  end
end
