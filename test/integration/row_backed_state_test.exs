defmodule AshJido.RowBackedStateTest do
  use ExUnit.Case, async: false

  alias AshJido.State
  alias Jido.AgentServer
  alias Jido.Persistence.{Codec.Term, Record, Store}

  defmodule SQLite do
    use AshSqlite.Repo, otp_app: :ash_jido

    def min_sqlite_version, do: %Version{major: 3, minor: 38, patch: 0}
    def write_transactions?, do: true
  end

  defmodule Postgres do
    use AshPostgres.Repo, otp_app: :ash_jido, warn_on_missing_ash_functions?: false

    def min_pg_version, do: %Version{major: 17, minor: 0, patch: 0}
  end

  defmodule CommitObserver do
    use Ash.Notifier

    @impl true
    def notify(%{action: %{name: :commit_state}, data: %{case_id: id}}) do
      case :persistent_term.get({__MODULE__, id}, nil) do
        {test, repo} -> send(test, {:notified, id, repo.in_transaction?()})
        nil -> :ok
      end
    end

    def notify(_notification), do: :ok
  end

  defmodule ResourceFields do
    defmacro __using__(kind) do
      {keys, create_fields} =
        if kind == :scoped do
          keys =
            quote do
              attribute :tenant_id, :string, primary_key?: true, allow_nil?: false
              attribute :case_id, :integer, primary_key?: true, allow_nil?: false
            end

          {keys, [:case_id]}
        else
          {quote(do: uuid_primary_key(:case_id)), []}
        end

      quote do
        attributes do
          unquote(keys)
          attribute :status, :atom, constraints: [one_of: [:open, :closed]], allow_nil?: false
          attribute :priority, :integer, constraints: [min: 1, max: 5], allow_nil?: false
          attribute :budget, :decimal, allow_nil?: false
          attribute :notes, :string
          attribute :version, :integer, allow_nil?: false, default: 1
        end

        actions do
          defaults [:read, create: unquote(create_fields ++ [:status, :priority, :budget, :notes])]

          update :commit_state do
            require_atomic? false
            accept [:status, :priority, :budget]
            change optimistic_lock(:version)

            change fn changeset, _context ->
              case Ash.Changeset.get_attribute(changeset, :priority) do
                1 -> Ash.Changeset.add_error(changeset, field: :priority, message: "reserved")
                5 -> Ash.Changeset.force_change_attribute(changeset, :priority, 4)
                _ -> changeset
              end
            end
          end
        end
      end
    end
  end

  defmodule SQLiteCase do
    use Ash.Resource,
      domain: AshJido.RowBackedStateTest.Domain,
      data_layer: AshSqlite.DataLayer,
      extensions: [AshJido],
      notifiers: [CommitObserver]

    sqlite do
      table "support_cases"
      repo(SQLite)
    end

    use ResourceFields

    jido do
      action :commit_state
    end
  end

  defmodule PostgresCase do
    use Ash.Resource,
      domain: AshJido.RowBackedStateTest.Domain,
      data_layer: AshPostgres.DataLayer,
      notifiers: [CommitObserver]

    postgres do
      table "support_cases"
      repo(Postgres)
    end

    use ResourceFields
  end

  defmodule SQLiteScopedCase do
    use Ash.Resource, domain: AshJido.RowBackedStateTest.Domain, data_layer: AshSqlite.DataLayer

    sqlite do
      table "scoped_cases"
      repo(SQLite)
    end

    multitenancy do
      strategy :attribute
      attribute :tenant_id
    end

    use ResourceFields, :scoped
  end

  defmodule PostgresScopedCase do
    use Ash.Resource, domain: AshJido.RowBackedStateTest.Domain, data_layer: AshPostgres.DataLayer

    postgres do
      table "scoped_cases"
      repo(Postgres)
    end

    multitenancy do
      strategy :attribute
      attribute :tenant_id
    end

    use ResourceFields, :scoped
  end

  defmodule SQLiteCheckpoint do
    use Ash.Resource,
      domain: AshJido.RowBackedStateTest.Domain,
      data_layer: AshSqlite.DataLayer,
      extensions: [AshJido]

    sqlite do
      table "agent_checkpoints"
      repo(SQLite)
    end

    jido do
      persistence_store()
    end
  end

  defmodule PostgresCheckpoint do
    use Ash.Resource,
      domain: AshJido.RowBackedStateTest.Domain,
      data_layer: AshPostgres.DataLayer,
      extensions: [AshJido]

    postgres do
      table "agent_checkpoints"
      repo(Postgres)
    end

    jido do
      persistence_store()
    end
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource SQLiteCase
      resource PostgresCase
      resource SQLiteScopedCase
      resource PostgresScopedCase
      resource SQLiteCheckpoint
      resource PostgresCheckpoint
    end
  end

  defmodule Reprioritize do
    use Jido.Action,
      name: "reprioritize_case",
      schema:
        Jido.Joi.object(%{
          priority: Jido.Joi.integer(),
          pause: Jido.Joi.default(Jido.Joi.boolean(), false),
          budget: Jido.Joi.optional(Jido.Joi.string())
        }),
      output_schema: Jido.Joi.map()

    @impl true
    def run(%{priority: priority, pause: pause} = params, %{agent_state: state}) do
      if pause do
        send(Process.whereis(AshJido.RowBackedStateTest), {:evaluating, self(), state.priority})

        receive do
          :continue -> :ok
        after
          5_000 -> raise "test did not release the Action"
        end
      end

      budget = if params[:budget], do: Decimal.new(params.budget), else: state.budget
      {:ok, %{state | priority: priority, budget: budget}}
    end
  end

  defmodule Approval do
    use Jido.Flow, name: "approve_case_priority"

    flow do
      await "approval", event: "case.approved"

      step "reprioritize", _approval <- result("approval"), inline: [context: context] do
        state = context.agent_state
        {:ok, %{state | priority: state.priority + 1}}
      end

      output result("reprioritize")
    end
  end

  defmodule AgentFixture do
    defmacro __using__(resource) do
      quote do
        use Jido.Agent, name: "support_case"
        import AshJido.State.DSL, only: [ash: 2]

        state do
          ash(unquote(resource),
            fields: [:status, :priority, :budget],
            read_only: [:notes],
            id: :primary_key,
            update: :commit_state
          )
        end

        routes do
          signal_source "/support/case"
          route "case.reprioritize", Reprioritize, as: :reprioritize
          route "case.request_approval", Approval
        end
      end
    end
  end

  defmodule SQLiteAgent do
    use AgentFixture, SQLiteCase
  end

  defmodule PostgresAgent do
    use AgentFixture, PostgresCase
  end

  defmodule SQLiteScopedAgent do
    use AgentFixture, SQLiteScopedCase
  end

  defmodule PostgresScopedAgent do
    use AgentFixture, PostgresScopedCase
  end

  describe "SQLite" do
    setup do
      dir = Path.join(System.tmp_dir!(), "ash-jido-state-#{System.unique_integer([:positive])}")
      File.mkdir!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      start_supervised!({SQLite, [database: Path.join(dir, "support.db"), pool_size: 4]})
      create_tables(SQLite, "TEXT", "BLOB", "TEXT")
      setup_binding(SQLite, SQLiteCase, SQLiteCheckpoint, SQLiteAgent)
    end

    test("commits the canonical row and receipt with a normal Signal", fixture, do: commits_and_restores(fixture))
    test("reports an external write conflict and refreshes for the next turn", fixture, do: external_update(fixture))
    test("rolls back a row update when the checkpoint conflicts", fixture, do: checkpoint_conflict(fixture))
    test("does not write a no-op or an invalid state", fixture, do: no_op_and_invalid(fixture))
    test("enforces one durable owner across partitions", fixture, do: duplicate_owner(fixture))
    test("retains the committed result after the caller and instance stop", fixture, do: lost_caller(fixture))
    test("keeps refreshed state private until commit", fixture, do: private_refresh(fixture))
    test("restores the admitted row state of a waiting Flow", fixture, do: restore_waiting_flow(fixture))
    test("rejects a restored Flow after the row version advances", fixture, do: restore_waiting_flow(fixture, :stale))
    test("starts a composite-key Agent in the selected tenant", do: scoped_start(SQLiteScopedCase, SQLiteScopedAgent))

    test "a generated action in the bound agent context cannot write its row", %{id: id, address: address} do
      params = %{case_id: id, priority: 4}

      assert {:error, %{details: %{reason: :ash_state_direct_mutation}}} =
               SQLiteCase.Jido.CommitState.run(params, %{agent_id: address.id, agent_module: SQLiteAgent})

      assert %{priority: 2, version: 1} = Ash.get!(SQLiteCase, id)
      assert {:ok, _envelope} = SQLiteCase.Jido.CommitState.run(params, %{})
      assert %{priority: 4, version: 2} = Ash.get!(SQLiteCase, id)
    end

    test "rejects an instance without its shared Ash checkpoint store", %{id: id, agent: agent} do
      start_supervised!({Jido, name: WithoutStore, namespace: "test/no-store"})

      assert {:error, %{code: :state_provider_requires_persistence}} = AshJido.start_agent(WithoutStore, agent, id)
    end
  end

  describe "PostgreSQL" do
    @describetag :postgres

    setup do
      postgres_database()
      create_tables(Postgres, "UUID", "BYTEA", "NUMERIC")
      setup_binding(Postgres, PostgresCase, PostgresCheckpoint, PostgresAgent)
    end

    test("commits the canonical row and receipt with a normal Signal", fixture, do: commits_and_restores(fixture))
    test("reports an external write conflict and refreshes for the next turn", fixture, do: external_update(fixture))
    test("rolls back a row update when the checkpoint conflicts", fixture, do: checkpoint_conflict(fixture))
    test("does not write a no-op or an invalid state", fixture, do: no_op_and_invalid(fixture))
    test("enforces one durable owner across partitions", fixture, do: duplicate_owner(fixture))
    test("retains the committed result after the caller and instance stop", fixture, do: lost_caller(fixture))
    test("keeps refreshed state private until commit", fixture, do: private_refresh(fixture))
    test("restores the admitted row state of a waiting Flow", fixture, do: restore_waiting_flow(fixture))
    test("rejects a restored Flow after the row version advances", fixture, do: restore_waiting_flow(fixture, :stale))

    test("starts a composite-key Agent in the selected tenant",
      do: scoped_start(PostgresScopedCase, PostgresScopedAgent)
    )
  end

  defp postgres_database do
    database = "ash_jido_test_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    opts = [
      hostname: "127.0.0.1",
      port: String.to_integer(System.fetch_env!("ASH_JIDO_POSTGRES_PORT")),
      username: "postgres",
      database: "postgres"
    ]

    {:ok, conn} = Postgrex.start_link(opts)
    Postgrex.query!(conn, "CREATE DATABASE #{database}", [])
    GenServer.stop(conn)

    on_exit(fn ->
      {:ok, conn} = Postgrex.start_link(opts)
      Postgrex.query!(conn, "DROP DATABASE #{database}", [])
      GenServer.stop(conn)
    end)

    start_supervised!({Postgres, Keyword.merge(opts, database: database, pool_size: 4)})
  end

  defp setup_binding(repo, resource, checkpoint, agent) do
    Process.register(self(), __MODULE__)

    row = Ash.create!(resource, %{status: :open, priority: 2, budget: "12.30"})
    store = {AshJido.Persistence.Adapter, [resource: checkpoint]}
    start_supervised!({Jido, name: Runtime, namespace: "test/ash-case-state", persistence: store})
    {:ok, address} = State.address(Runtime, agent, row.case_id)
    {:ok, server} = AshJido.start_agent(Runtime, agent, row.case_id)
    observer = {CommitObserver, row.case_id}
    :persistent_term.put(observer, {self(), repo})
    on_exit(fn -> :persistent_term.erase(observer) end)
    %{resource: resource, id: row.case_id, address: address, server: server, store: store, agent: agent}
  end

  defp create_tables(repo, id_type, binary_type, decimal_type) do
    repo.query!("""
    CREATE TABLE scoped_cases (
      tenant_id TEXT NOT NULL,
      case_id BIGINT NOT NULL,
      status TEXT NOT NULL,
      priority BIGINT NOT NULL,
      budget #{decimal_type} NOT NULL,
      notes TEXT,
      version BIGINT NOT NULL DEFAULT 1,
      PRIMARY KEY (tenant_id, case_id)
    )
    """)

    repo.query!("""
    CREATE TABLE support_cases (
      case_id #{id_type} PRIMARY KEY NOT NULL,
      status TEXT NOT NULL,
      priority BIGINT NOT NULL,
      budget #{decimal_type} NOT NULL,
      notes TEXT,
      version BIGINT NOT NULL DEFAULT 1
    )
    """)

    repo.query!("""
    CREATE TABLE agent_checkpoints (
      key #{binary_type} PRIMARY KEY NOT NULL,
      value #{binary_type} NOT NULL,
      write_token #{binary_type} NOT NULL
    )
    """)
  end

  defp commits_and_restores(fixture) do
    %{resource: resource, id: id, address: address, server: server, agent: agent} = fixture

    assert %{agent: %{state: %{status: :open, priority: 2, budget: budget, notes: nil, version: 1}}} =
             AgentServer.snapshot(server)

    assert Decimal.equal?(budget, Decimal.new("12.30"))

    pending =
      Jido.submit(Runtime, address, agent.reprioritize_signal!(%{priority: 5}),
        result_handoff: true,
        turn_id: "save-case"
      )

    assert {:ok, %{status: :committed, durability: :durable}} = AgentServer.await(pending)
    assert_receive {:notified, ^id, false}, 2_000
    assert %{priority: 4, version: 2} = Ash.get!(resource, id)
    assert %{agent: %{state: %{priority: 4, version: 2}}} = AgentServer.snapshot(server)
    assert {:ok, %{status: :committed, turn_id: "save-case"}} = Jido.turn_result(Runtime, address, "save-case")

    assert :ok = Jido.stop_agent(Runtime, server)
    assert {:ok, restored} = Jido.activate_agent(Runtime, address)
    assert %{agent: %{state: %{priority: 4, version: 2}}} = AgentServer.snapshot(restored)
    assert {:ok, %{status: :committed, turn_id: "save-case"}} = Jido.turn_result(Runtime, address, "save-case")
  end

  defp external_update(fixture) do
    {task, action} = pause_turn(fixture)
    Ash.get!(fixture.resource, fixture.id) |> Ash.update!(%{priority: 3}, action: :commit_state)
    send(action, :continue)
    assert {:ok, %{status: :failed, error: :ash_state_stale_row}} = Task.await(task)
    assert %{priority: 3, version: 2} = Ash.get!(fixture.resource, fixture.id)
    assert %{agent: %{state: %{priority: 2, version: 1}}} = AgentServer.snapshot(fixture.server)
    assert {:ok, %{status: :committed}} = call(fixture, 4)
    assert %{priority: 4, version: 3} = Ash.get!(fixture.resource, fixture.id)
  end

  defp checkpoint_conflict(fixture) do
    {task, action} = pause_turn(fixture)
    key = Record.agent_key(fixture.address)
    assert {:ok, bytes, token} = Store.read(fixture.store, key)
    assert {:ok, record} = Term.decode(bytes, [])
    assert {:ok, competing} = Term.encode(Map.update!(record, :rev, &(&1 + 1)))
    assert :ok = Store.compare_and_swap(fixture.store, key, token, competing)
    send(action, :continue)

    assert {:ok, %{status: :uncertain}} = Task.await(task)
    refute_received {:notified, _, _}
    assert %{priority: 2, version: 1} = Ash.get!(fixture.resource, fixture.id)
    assert {:ok, ^competing, _} = Store.read(fixture.store, key)
  end

  defp no_op_and_invalid(fixture) do
    assert {:ok, %{status: :committed}} = call(fixture, 2)
    signal = fixture.agent.reprioritize_signal!(%{priority: 2, budget: "12.300"})
    assert {:ok, %{status: :committed}} = AgentServer.call(fixture.server, signal)
    assert %{priority: 2, version: 1} = Ash.get!(fixture.resource, fixture.id)
    assert {:ok, %{status: :failed}} = call(fixture, 6)
    assert {:ok, %{status: :failed, error: :ash_state_invalid_action}} = call(fixture, 1)
    assert %{priority: 2, version: 1} = Ash.get!(fixture.resource, fixture.id)
  end

  defp duplicate_owner(fixture) do
    assert {:error, %{code: :ash_state_row_already_bound}} =
             AshJido.start_agent(Runtime, fixture.agent, fixture.id, partition: "different")

    assert :ok = Jido.stop_agent(Runtime, fixture.server)
    assert :ok = Jido.delete_agent(Runtime, fixture.address)
    assert %{priority: 2, version: 1} = Ash.get!(fixture.resource, fixture.id)
  end

  defp scoped_start(resource, agent) do
    for {tenant, priority} <- [{"west", 2}, {"east", 3}] do
      Ash.create!(resource, %{case_id: 42, status: :open, priority: priority, budget: "12.30"}, tenant: tenant)
    end

    west = %{tenant_id: "west", case_id: 42}
    east = %{tenant_id: "east", case_id: 42}

    assert {:error, %{code: :ash_state_source_required, message: message}} = Jido.start_agent(Runtime, agent)
    assert message =~ "AshJido.row(primary_key)"

    assert {:error, %{code: :invalid_ash_state_tenant}} = AshJido.start_agent(Runtime, agent, west)

    assert {:error, %{code: :invalid_ash_state_identity, message: message}} =
             AshJido.start_agent(Runtime, agent, %{case_id: 42}, tenant: "west")

    assert message =~ ":case_id"
    assert message =~ ":tenant_id"

    assert {:error, %{code: :state_source_owns_id}} =
             Jido.start_agent(Runtime, agent, id: "custom", state: AshJido.row(west, tenant: "west"))

    assert {:error, %{code: :ash_state_row_not_found}} =
             Jido.start_agent(Runtime, agent, state: AshJido.row(west, tenant: "east"))

    assert {:ok, west_server} =
             Jido.start_agent(Runtime, agent, state: AshJido.row(%{west | case_id: "42"}, tenant: "west"))

    assert {:ok, east_server} = AshJido.start_agent(Runtime, agent, east, tenant: "east")
    assert {:ok, west_address} = State.address(Runtime, agent, west, tenant: "west")
    assert {:ok, east_address} = State.address(Runtime, agent, east, tenant: "east")
    assert west_address.id != east_address.id
    assert %{agent: %{id: west_id, state: %{priority: 2}}} = AgentServer.snapshot(west_server)
    assert %{agent: %{id: east_id, state: %{priority: 3}}} = AgentServer.snapshot(east_server)
    assert west_id == west_address.id
    assert east_id == east_address.id

    assert {:ok, %{status: :committed}} = AgentServer.call(west_server, agent.reprioritize_signal!(%{priority: 4}))
    assert %{priority: 4, version: 2} = Ash.get!(resource, west, tenant: "west")
    assert %{priority: 3, version: 1} = Ash.get!(resource, east, tenant: "east")

    assert :ok = Jido.stop_agent(Runtime, west_server)
    assert {:ok, resumed} = Jido.activate_agent(Runtime, west_address)
    assert %{agent: %{state: %{priority: 4, version: 2}}} = AgentServer.snapshot(resumed)
  end

  defp lost_caller(%{address: address, agent: agent, id: id, store: store, resource: resource}) do
    signal = agent.reprioritize_signal!(%{priority: 4, pause: true})

    {caller, monitor} =
      spawn_monitor(fn ->
        Runtime
        |> Jido.submit(address, signal, turn_id: "lost-caller", result_handoff: true)
        |> AgentServer.await()
      end)

    assert_receive {:evaluating, action, 2}, 2_000
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^caller, :killed}, 2_000
    send(action, :continue)
    assert_receive {:notified, ^id, false}, 2_000
    stop_supervised!(Runtime)
    start_supervised!({Jido, name: Runtime, namespace: "test/ash-case-state", persistence: store})

    assert {:ok, %{status: :committed, turn_id: "lost-caller"}} = Jido.turn_result(Runtime, address, "lost-caller")
    assert %{priority: 4, version: 2} = Ash.get!(resource, id)
    assert {:ok, restored} = Jido.activate_agent(Runtime, address)
    assert %{agent: %{state: %{priority: 4, version: 2}}} = AgentServer.snapshot(restored)
  end

  defp private_refresh(%{resource: resource, id: id, server: server} = fixture) do
    Ash.get!(resource, id) |> Ash.update!(%{priority: 3}, action: :commit_state)
    {task, action} = pause_turn(fixture, 1, 3)
    assert %{agent: %{state: %{priority: 2, version: 1}}} = AgentServer.snapshot(server)
    send(action, :continue)
    assert {:ok, %{status: :failed, error: :ash_state_invalid_action}} = Task.await(task)
    assert %{agent: %{state: %{priority: 2, version: 1}}} = AgentServer.snapshot(server)
    assert %{priority: 3, version: 2} = Ash.get!(resource, id)
    assert {:ok, %{status: :committed}} = call(fixture, 4)
    assert %{agent: %{state: %{priority: 4, version: 3}}} = AgentServer.snapshot(server)
  end

  defp restore_waiting_flow(fixture, outcome \\ :committed) do
    %{address: address, resource: resource, id: id, server: server, store: store} = fixture
    Ash.get!(resource, id) |> Ash.update!(%{priority: 3}, action: :commit_state)
    request = Jido.Signal.new!("case.request_approval", %{}, source: "/support/case")

    assert {:ok, %{status: :waiting, turn_id: turn_id}} = Jido.call(Runtime, address, request)
    assert %{agent: %{state: %{priority: 2, version: 1}}} = AgentServer.snapshot(server)
    stop_supervised!(Runtime)
    start_supervised!({Jido, name: Runtime, namespace: "test/ash-case-state", persistence: store})

    approval = Jido.Signal.new!("case.approved", %{}, source: "/support/case")

    case outcome do
      :committed ->
        assert {:ok, %{status: :committed, turn_id: ^turn_id}} = Jido.call(Runtime, address, approval)
        assert %{priority: 4, version: 3} = Ash.get!(resource, id)

      :stale ->
        Ash.get!(resource, id) |> Ash.update!(%{status: :closed}, action: :commit_state)

        assert {:ok, %{status: :failed, error: :ash_state_stale_row, turn_id: ^turn_id}} =
                 Jido.call(Runtime, address, approval)

        assert %{priority: 3, status: :closed, version: 3} = Ash.get!(resource, id)
    end
  end

  defp pause_turn(fixture, priority \\ 4, prior_priority \\ 2) do
    signal = fixture.agent.reprioritize_signal!(%{priority: priority, pause: true})
    task = Task.async(fn -> AgentServer.call(fixture.server, signal) end)
    assert_receive {:evaluating, pid, ^prior_priority}, 2_000
    {task, pid}
  end

  defp call(fixture, priority),
    do: AgentServer.call(fixture.server, fixture.agent.reprioritize_signal!(%{priority: priority}))
end
