defmodule AshJido.AshStateTest do
  use ExUnit.Case, async: false

  alias AshJido.State
  alias Jido.AgentServer
  alias Jido.AgentServer.TurnResult

  defmodule Repo do
    use AshSqlite.Repo, otp_app: :ash_jido

    def min_sqlite_version, do: %Version{major: 3, minor: 38, patch: 0}
    def write_transactions?, do: true
  end

  defmodule Row do
    use Ash.Resource, domain: AshJido.AshStateTest.Domain, data_layer: AshSqlite.DataLayer

    sqlite do
      table "counters"
      repo(Repo)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:count, :integer, allow_nil?: false, constraints: [min: 0])
      attribute(:lock_version, :integer, allow_nil?: false, default: 1)
    end

    actions do
      defaults([:read, create: [:count], update: [:count]])

      update :set_count do
        accept([:count])
        require_atomic?(false)
        change(optimistic_lock(:lock_version))
      end
    end
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource(Row)
    end
  end

  defmodule AdmissionBarrier do
    use Jido.Plugin

    @impl true
    def admit(_runtime, %{caller_context: %{writer: writer}}, _opts) do
      send(writer, {:row_loaded, self()})

      receive do
        :write_finished -> {:ok, nil}
      end
    end

    def admit(_runtime, _admission, _opts), do: {:ok, nil}
  end

  defmodule Add do
    use Jido.Action, name: "ash_state_add", schema: Jido.Joi.object(%{by: Jido.Joi.integer()})

    @impl true
    def run(%{by: by}, context) do
      row = context.plugin_inputs[State].runtime.row
      proposal = %{count: row.count + by}
      {:ok, proposal, [State.update(proposal)]}
    end
  end

  defmodule Counter do
    use Jido.Agent, name: "ash_state_counter"
    import AshJido.State, only: [ash: 2]

    state do
      ash(Row, update: :set_count)
    end

    # Pause after the state plugin has read the row in the conflict test.
    Jido.Agent.DSL.register_plugin!(AdmissionBarrier, __ENV__)

    routes do
      signal_source "/test/ash-state"

      route "ash_state.add", Add, as: :add do
        state(:unchanged)
      end

      route "ash_state.read", as: :read do
        action _params, context: context do
          {:ok, %{count: context.plugin_inputs[State].runtime.row.count}}
        end

        state(:unchanged)
        reply("ash_state.current", from: output())
      end
    end
  end

  @moduletag :tmp_dir
  setup %{tmp_dir: path} do
    start_supervised!({Repo, database: Path.join(path, "ash_state.db"), pool_size: 1})

    Ecto.Adapters.SQL.query!(Repo, """
    CREATE TABLE counters (
      id BLOB PRIMARY KEY NOT NULL,
      count INTEGER NOT NULL,
      lock_version INTEGER NOT NULL
    )
    """)

    %{row: Ash.create!(Row, %{count: 10})}
  end

  test "the configured update action must apply optimistic locking" do
    assert {:error, :invalid_ash_state_resource} = State.normalize(%{resource: Row, update: :update})
  end

  test "ash must appear inside the Agent state block" do
    assert_raise CompileError, ~r/declare ash inside the Agent's state block/, fn ->
      Code.compile_string("""
      defmodule #{inspect(__MODULE__.AshOutsideState)} do
        use Jido.Agent, name: "ash_outside_state"
        import AshJido.State, only: [ash: 2]

        ash #{inspect(Row)}, update: :set_count
      end
      """)
    end
  end

  test "ash rejects other state declarations" do
    for declaration <- ["schema Jido.Joi.object(%{})", "initial_state %{}", "ecto #{inspect(Row)}"] do
      assert_raise Spark.Error.DslError, ~r/ash cannot be combined/, fn ->
        Code.compile_string("""
        defmodule #{inspect(__MODULE__.ConflictingState)} do
          use Jido.Agent, name: "ash_conflicting_state"
          import AshJido.State, only: [ash: 2]

          state do
            ash #{inspect(Row)}, update: :set_count
            #{declaration}
          end
        end
        """)
      end
    end
  end

  test "a stale proposal fails and the next Turn reads the newer row", %{row: row} do
    server = start_counter(row.id)

    assert {:ok, %TurnResult{status: :committed}} = AgentServer.call(server, add_signal(2))
    assert %{count: 12, lock_version: 2} = row = Ash.get!(Row, row.id)

    pending = AgentServer.submit(server, add_signal(2), context: %{writer: self()})
    assert_receive {:row_loaded, admission}, 2_000
    assert %{count: 40, lock_version: 3} = Ash.update!(row, %{count: 40}, action: :set_count)
    send(admission, :write_finished)

    assert {:ok, %TurnResult{status: :failed, error: :stale_ash_state}} = AgentServer.await(pending)
    assert %{count: 40, lock_version: 3} = Ash.get!(Row, row.id)

    assert {:ok, %TurnResult{status: :committed}} = AgentServer.call(server, add_signal(2))
    assert %{count: 42, lock_version: 4} = Ash.get!(Row, row.id)
  end

  test "Jido persistence allows reads and rejects row writes", %{row: row, tmp_dir: path} do
    server = start_counter(row.id, {Jido.Persistence.File, path: Path.join(path, "jido")})

    assert {:ok, %TurnResult{status: :failed, durability: :durable, error: :ash_state_requires_memory_turn}} =
             AgentServer.call(server, add_signal(2))

    assert {:ok, %TurnResult{status: :committed, durability: :durable, reply: %{data: %{count: 10}}}} =
             AgentServer.call(server, Counter.read_signal!())

    assert %{count: 10, lock_version: 1} = Ash.get!(Row, row.id)
  end

  defp add_signal(by), do: Counter.add_signal!(%{by: by})

  defp start_counter(id, persistence \\ false) do
    start_supervised!({Jido, name: __MODULE__.Instance, namespace: "test/ash-state", persistence: persistence})
    assert {:ok, server} = Jido.start_agent(__MODULE__.Instance, Counter, id: id)
    assert :ok = AgentServer.await_ready(server)
    server
  end
end
