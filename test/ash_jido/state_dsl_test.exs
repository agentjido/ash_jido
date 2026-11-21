defmodule AshJido.StateDSLTest do
  use ExUnit.Case, async: true

  defmodule Resource do
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets

    attributes do
      attribute :part, :string, primary_key?: true, allow_nil?: false
      attribute :number, :integer, primary_key?: true, allow_nil?: false
      attribute :status, :string, allow_nil?: false
      attribute :version, :integer, allow_nil?: false, default: 1
    end

    actions do
      defaults [:read]

      update :commit_state do
        accept [:status]
        change optimistic_lock(:version)
      end

      update :unsafe do
        accept [:status]
      end
    end
  end

  @ash "ash #{inspect(Resource)}, fields: [:status], id: :primary_key, update: :commit_state"
  @schema "schema Jido.Joi.object(%{status: Jido.Joi.string()})"

  test "rejects repeated and mixed schema sources in either order" do
    for {first, second} <- [{@ash, @ash}, {@ash, @schema}, {@schema, @ash}, {@schema, @schema}] do
      assert_raise CompileError, ~r/Agent state accepts exactly one schema source/, fn ->
        compile("state do\n#{first}\n#{second}\nend")
      end
    end
  end

  test "rejects an explicit identical schema and a second state block" do
    [{module, _}] = compile("state do\n#{@ash}\nend")

    assert_raise CompileError, ~r/Agent state accepts exactly one schema source/, fn ->
      compile("state do\n#{@ash}\nschema #{inspect(module)}.schema()\nend")
    end

    assert_raise CompileError, ~r/Agent section state can be declared only once/, fn ->
      compile("state do\n#{@ash}\nend\nstate do\n#{@ash}\nend")
    end
  end

  test "rejects invalid projection and action declarations" do
    for {expression, failure} <- [
          {@ash <> ", id: :primary_key", ~r/unique supported keyword options/},
          {String.replace(@ash, "[:status]", "[:status, :status]"), ~r/unique field names/},
          {String.replace(@ash, "[:status]", "[:missing]"), ~r/field :missing is not an attribute accepted/},
          {String.replace(@ash, ":commit_state", ":unsafe"), ~r/unconditional optimistic_lock/},
          {String.replace(@ash, "[:status]", "[:part]"), ~r/writable fields overlap/}
        ] do
      assert_raise CompileError, failure, fn ->
        compile("state do\n#{expression}\nend")
      end
    end

    assert_raise CompileError, ~r/ash must be declared inside state do/, fn -> compile(@ash) end
  end

  test "encodes canonical composite keys and checks resource types" do
    [{module, _}] = compile("state do\n#{@ash}\nend")
    {AshJido.State, descriptor, _schema} = module.__jido_state_provider__()

    assert {:ok, id} = AshJido.State.Identity.encode(descriptor, %{part: "a", number: "2"}, nil)
    assert {:ok, %{part: "a", number: 2}, nil} = AshJido.State.Identity.decode(descriptor, id)
    assert {:ok, ^id} = AshJido.State.Identity.encode(descriptor, %{number: 2, part: "a"}, nil)

    assert {:error, :invalid_ash_state_identity} =
             AshJido.State.Identity.encode(descriptor, %{part: "a"}, nil)
  end

  defp compile(body) do
    module = Module.concat(__MODULE__, "Probe#{System.unique_integer([:positive])}")

    Code.compile_string("""
    defmodule #{inspect(module)} do
      use Jido.Agent, name: "row_state_probe"
      import AshJido.State.DSL, only: [ash: 2]
      #{body}
    end
    """)
  end
end
