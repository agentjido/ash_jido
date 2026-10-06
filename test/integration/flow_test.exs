defmodule AshJido.V3FlowTest do
  use ExUnit.Case, async: false

  defmodule CreateAndFetchFlow do
    use Jido.Flow, name: "ash_jido_create_and_fetch"

    flow do
      step "create",
        action: AshJido.Test.Domain.Jido.RegisterUser,
        params: %{
          name: input(:name),
          email: input(:email)
        }

      step "fetch",
        action: AshJido.Test.Domain.Jido.GetUser,
        params: %{
          id: result("create", [:result, :id])
        }

      output result("fetch")
    end
  end

  defmodule ParallelCalculationsFlow do
    use Jido.Flow, name: "ash_jido_parallel_calculations"

    flow do
      step "left",
        action: AshJido.Test.Domain.Jido.DoubleValue,
        params: %{value: input(:left)}

      step "right",
        action: AshJido.Test.Domain.Jido.DoubleValue,
        params: %{value: input(:right)}

      output %{
        left: result("left", :result),
        right: result("right", :result)
      }
    end
  end

  test "generated Actions compose in a sequential Jido Flow" do
    email = "flow-#{System.unique_integer([:positive])}@example.com"

    assert {:ok, %{result: %{email: ^email}}} =
             Jido.Exec.run(CreateAndFetchFlow, %{name: "Flow User", email: email}, %{})
  end

  test "independent generated Actions compose in a parallel Jido Flow" do
    assert {:ok, %{left: 6, right: 10}} =
             Jido.Exec.run(ParallelCalculationsFlow, %{left: 3, right: 5}, %{}, max_concurrency: 2)
  end

  test "AshJido does not add a second Flow runtime" do
    refute Code.ensure_loaded?(AshJido.Flow)
  end
end
