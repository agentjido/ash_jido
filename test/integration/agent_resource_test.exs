defmodule AshJido.AgentResourceTest do
  use ExUnit.Case, async: false

  alias Jido.Agent.Address
  alias Jido.Joi

  @instance __MODULE__.Instance
  @namespace "test/agent-resource"
  @moduletag :tmp_dir

  defmodule Actor do
    use Ash.Resource, data_layer: :embedded

    attributes do
      attribute(:id, :string, primary_key?: true, allow_nil?: false)
      attribute(:credential, :string, sensitive?: true)
    end
  end

  defmodule Resolver do
    @behaviour AshJido.ActorScope

    @impl true
    def reference(%Actor{id: id}, _context), do: {:ok, %{type: "user", id: id}}

    @impl true
    def resolve_actor(%{type: "user", id: id}, _context), do: {:ok, %Actor{id: id}}
  end

  defmodule Wait do
    use Jido.Flow, name: "ash_agent_resource_wait"

    flow do
      await("finish", event: "finish")
      output(result("finish"))
    end
  end

  defmodule Counter do
    use Jido.Agent, name: "ash_agent_resource_counter"

    state do
      schema Joi.object(%{count: Joi.default(Joi.integer(), 0), hidden: Joi.default(Joi.string(), "private")})
    end

    routes do
      signal_source("/test/ash-agent-resource")

      route "counter.set", as: :set_count do
        action %{count: count},
          context: context,
          schema: Joi.object(%{count: Joi.integer()}),
          output_schema: Joi.object(%{state: Joi.object(%{count: Joi.integer(), hidden: Joi.string()})}) do
          {:ok, %{state: %{context.agent_state | count: count}}}
        end

        state(from: output(:state))
      end

      route "counter.wait", Wait, as: :wait do
        state(:unchanged)
      end

      route "counter.private", as: :private_route do
        action _params do
          {:ok, %{}}
        end

        state(:unchanged)
      end

      route "counter.literal", as: :literal do
        action _params, schema: Joi.object(%{value: Joi.literal("exact")}) do
          {:ok, %{}}
        end

        state(:unchanged)
      end

      route "counter.nested", as: :nested do
        action _params,
          schema:
            Joi.object(%{
              items: Joi.list(Joi.object(%{name: Joi.string(), kind: Joi.enum([:open, :closed])}))
            }) do
          {:ok, %{}}
        end

        state(:unchanged)
      end

      route "other.*" do
        action _params do
          {:ok, %{}}
        end

        state(:unchanged)
      end

      route "other.overlap", as: :overlap do
        action _params, schema: Joi.object(%{}) do
          {:ok, %{}}
        end

        state(:unchanged)
      end
    end
  end

  defmodule Other do
    use Jido.Agent, name: "ash_agent_resource_other"
  end

  defmodule Resource do
    use Ash.Resource,
      domain: AshJido.AgentResourceTest.Domain,
      authorizers: [Ash.Policy.Authorizer],
      extensions: [AshJido.Agent]

    jido_agent do
      agent(Counter)
      instance(AshJido.AgentResourceTest.Instance)
      expose_lifecycle([:start, :activate, :inspect, :status, :stop])
      expose_routes([:set_count, :wait, :nested])
      expose_state([:count])
      route_arguments(wait: [])
    end

    policies do
      policy always() do
        authorize_if(actor_present())
      end
    end
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource(Resource)
    end
  end

  setup %{tmp_dir: path} do
    previous = Application.fetch_env(:ash_jido, :actor_resolver)
    Application.put_env(:ash_jido, :actor_resolver, Resolver)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:ash_jido, :actor_resolver, value)
        :error -> Application.delete_env(:ash_jido, :actor_resolver)
      end
    end)

    persistence = {Jido.Persistence.File, path: path}
    start_supervised!({Jido, name: @instance, namespace: @namespace, persistence: persistence})
    {:ok, address} = Jido.agent_address(@instance, "counter", partition: "east")

    {:ok, address: address, actor: %Actor{id: "user-1", credential: "private-credential"}}
  end

  test "exposes allowed actions and projects a committed snapshot", %{address: address, actor: actor} do
    refute Ash.Resource.Info.action(Resource, :private_route)
    refute Ash.Resource.Info.action(Resource, :read)

    map = Address.to_map!(address)
    assert {:ok, ^map} = run(:start, address, actor)
    assert {:ok, %{residency: :active, address: ^map}} = run(:status, map, actor)
    assert {:ok, %Resource{count: 0, state_version: 0}} = run(:inspect, address, actor)
    assert {:ok, %{status: :committed, state_version: 1}} = run(:set_count, map, actor, %{count: 7})

    assert {:ok, %Resource{id: "counter", partition: "east", count: 7, state_version: 1} = projection} =
             run(:inspect, address, actor)

    refute Map.has_key?(projection, :hidden)
    assert {:ok, ^map} = run(:stop, address, actor)
    assert {:error, _reason} = run(:inspect, address, actor)
    assert {:ok, %{residency: :passivated}} = run(:status, address, actor)
    assert {:error, _reason} = run(:start, address, actor)
    assert {:ok, ^map} = run(:activate, address, actor)
    assert {:ok, %Resource{count: 7, state_version: 1}} = run(:inspect, address, actor)
  end

  test "requires authorization and rejects operations on the wrong Agent type", %{address: address, actor: actor} do
    assert {:error, %Ash.Error.Forbidden{}} = run(:start, address, nil)
    assert {:error, _reason} = run(:start, address, actor, %{}, authorize?: false)
    assert {:error, _reason} = run(:activate, address, actor)
    assert {:error, :not_found} = Jido.resolve_agent(@instance, address)

    assert {:ok, server} = Jido.start_agent(@instance, Other, id: address.id, partition: address.partition)
    assert :ok = Jido.AgentServer.await_ready(server)
    assert {:error, _reason} = run(:stop, address, actor)
    assert {:error, _reason} = run(:activate, address, actor)
    assert {:ok, ^server} = Jido.resolve_agent(@instance, address)
  end

  test "casts nested route arguments and checks instance identity", %{address: address, actor: actor} do
    wrong_namespace = %{address | namespace: "test/different-instance"}
    assert {:error, _reason} = run(:start, wrong_namespace, actor)
    assert {:error, :not_found} = Jido.resolve_agent(@instance, address)

    assert {:ok, _address} = run(:start, address, actor)

    assert {:ok, %{status: :committed}} =
             run(:nested, address, actor, %{items: [%{name: " open ", kind: "open"}]})

    assert {:error, %Ash.Error.Invalid{}} =
             run(:nested, address, actor, %{items: [%{name: "open", kind: "other"}]})
  end

  test "stores the actor reference in a pending durable Turn", %{address: address, actor: actor, tmp_dir: path} do
    assert {:ok, _address} = run(:start, address, actor)
    assert {:ok, %{status: :waiting}} = run(:wait, address, actor)

    assert {:ok, _agent, _record_version, _agent_version, receipt} =
             Jido.Persistence.load_agent_with_server_turn(@instance, Counter, address.id,
               namespace: address.namespace,
               partition: address.partition
             )

    encoded = :erlang.term_to_binary(receipt)
    assert encoded =~ "user-1"
    assert encoded =~ "actor_ref"
    refute encoded =~ actor.credential
    refute encoded =~ Atom.to_string(Actor)

    entries = Path.wildcard(Path.join(path, "**/*")) |> Enum.filter(&File.regular?/1)
    refute Enum.any?(entries, &(File.read!(&1) =~ actor.credential))
  end

  test "rejects duplicate, reserved, wildcard, and unsupported routes during compilation" do
    assert_raise RuntimeError, ~r/duplicate Ash action names/, fn ->
      compile_resource("expose_routes [:set_count, :set_count]")
    end

    assert_raise RuntimeError, ~r/reserved lifecycle name/, fn ->
      compile_resource("expose_routes [:delete]")
    end

    assert_raise RuntimeError, ~r/must select one exact/, fn ->
      compile_resource("expose_routes [:wildcard]")
    end

    assert_raise RuntimeError, ~r/must select one exact/, fn ->
      compile_resource("expose_routes [:overlap]")
    end

    assert_raise RuntimeError, ~r/requires explicit Ash arguments/, fn ->
      compile_resource("expose_routes [:wait]")
    end

    assert_raise RuntimeError, ~r/unsupported Ash mapping/, fn ->
      compile_resource("expose_routes [:literal]")
    end
  end

  defp compile_resource(config) do
    name = Module.concat(__MODULE__, "Invalid#{System.unique_integer([:positive])}")

    Code.compile_string("""
    defmodule #{inspect(name)} do
      use Ash.Resource, domain: nil, extensions: [AshJido.Agent]

      jido_agent do
        agent #{inspect(Counter)}
        instance #{inspect(@instance)}
        #{config}
      end
    end
    """)
  end

  defp run(action, address, actor, args \\ %{}, options \\ []) do
    opts = Keyword.merge([actor: actor, authorize?: true], options)

    Resource
    |> Ash.ActionInput.for_action(action, Map.put(args, :address, address), opts)
    |> Ash.run_action(opts)
  end
end
