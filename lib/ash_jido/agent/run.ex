defmodule AshJido.Agent.Run do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias Jido.Agent.Address
  alias Jido.Agent.Route
  alias Jido.AgentServer
  alias Jido.AgentServer.{Snapshot, Status, TurnResult}

  @impl true
  def run(_input, _opts, %{authorize?: false}), do: invalid(:authorization_required)

  def run(input, opts, context) do
    instance = Keyword.fetch!(opts, :instance)

    with {:ok, address} <- parse_address(input.arguments.address),
         {:ok, ^address} <- Jido.agent_address(instance, address.id, partition: address.partition),
         {:ok, _} = result <- perform(Keyword.fetch!(opts, :operation), address, input, opts, context) do
      result
    else
      {:error, reason} when is_atom(reason) -> invalid(reason)
      _other -> invalid(:operation_failed)
    end
  catch
    :exit, {:timeout, _call} -> invalid(:timeout)
    :exit, {:noproc, _call} -> invalid(:not_found)
    :exit, {:normal, _call} -> invalid(:not_found)
    :exit, {:shutdown, _call} -> invalid(:not_found)
  end

  defp parse_address(%Address{} = address), do: Address.validate(address)
  defp parse_address(address), do: Address.from_map(address)

  defp perform(:start, address, _input, opts, _context) do
    with {:ok, server} <- Jido.start_agent(opts[:instance], opts[:agent], identity_options(address)),
         :ok <- AgentServer.await_ready(server) do
      Address.to_map(address)
    end
  end

  defp perform(:activate, address, _input, opts, _context) do
    with {:ok, server} <- activate(address, opts),
         :ok <- AgentServer.await_ready(server),
         {:ok, _snapshot} <- checked_snapshot(server, address, opts[:agent]) do
      Address.to_map(address)
    end
  end

  defp perform(:inspect, address, input, opts, _context) do
    with {:ok, _server, snapshot} <- live_snapshot(opts, address) do
      fields = Map.take(snapshot.agent.state, opts[:fields])

      if public_value?(fields) do
        attrs =
          Map.merge(fields, %{id: address.id, partition: address.partition, state_version: snapshot.agent_revision})

        {:ok, struct!(input.resource, attrs)}
      else
        {:error, :unportable_state}
      end
    end
  end

  defp perform(:status, address, _input, opts, _context) do
    case live_snapshot(opts, address) do
      {:ok, server, _snapshot} ->
        server
        |> AgentServer.status()
        |> public_status(address)

      {:error, :not_found} ->
        instance = opts[:instance]
        lookup = Keyword.put(identity_options(address), :namespace, address.namespace)

        with {:ok, _agent} <-
               Jido.Persistence.load_agent(instance, opts[:agent], address.id, Keyword.delete(lookup, :id)) do
          instance
          |> Jido.status(address)
          |> public_status(address)
        end

      error ->
        error
    end
  end

  defp perform(:stop, address, _input, opts, _context) do
    with {:ok, server, _snapshot} <- live_snapshot(opts, address),
         {:ok, _final} <- AgentServer.stop(server) do
      Address.to_map(address)
    end
  end

  defp perform({:route, name, path, handler}, address, input, opts, context) do
    with {:ok, server, snapshot} <- live_snapshot(opts, address),
         {:ok, [%{as: ^name, handler: ^handler}]} <- Route.matching(snapshot.agent, path),
         {:ok, caller_context} <- AshJido.ActorScope.caller_context(context.actor, context.tenant),
         params = Map.delete(input.arguments, :address),
         {:ok, signal} <- Jido.Agent.DSL.input_signal(snapshot.agent, path, params),
         {:ok, %TurnResult{} = result} <- AgentServer.call(server, signal, context: caller_context) do
      {:ok,
       %{
         address: Address.to_map!(address),
         turn_id: result.turn_id,
         status: result.status,
         state_version: result.agent_revision,
         effects: result.effects
       }}
    end
  end

  defp activate(address, opts) do
    case Jido.resolve_agent(opts[:instance], address) do
      {:error, :not_found} ->
        Jido.thaw(opts[:instance], opts[:agent], address.id, partition: address.partition)

      other ->
        other
    end
  end

  defp live_snapshot(opts, address) do
    with {:ok, server} <- Jido.resolve_agent(opts[:instance], address),
         {:ok, snapshot} <- checked_snapshot(server, address, opts[:agent]) do
      {:ok, server, snapshot}
    end
  end

  defp checked_snapshot(server, address, agent) do
    case AgentServer.snapshot(server) do
      %Snapshot{agent: %{module: ^agent}, agent_address: ^address} = snapshot -> {:ok, snapshot}
      %Snapshot{} -> {:error, :wrong_agent_type}
      {:error, _reason} = error -> error
    end
  end

  defp public_status(%Status{} = status, address) do
    result = Map.take(status, [:admission, :durability, :effects, :lifecycle, :ready?, :residency, :work_state])
    {:ok, Map.merge(result, %{address: Address.to_map!(address), state_version: status.agent_revision})}
  end

  defp public_status({:error, _reason} = error, _address), do: error

  defp identity_options(address), do: [id: address.id, partition: address.partition]

  defp public_value?(value) when is_binary(value) or is_number(value) or is_atom(value), do: true
  defp public_value?(%Date{}), do: true
  defp public_value?(values) when is_list(values), do: Enum.all?(values, &public_value?/1)

  defp public_value?(value) when is_map(value) and not is_struct(value) do
    Enum.all?(value, fn {key, item} -> (is_atom(key) or is_binary(key)) and public_value?(item) end)
  end

  defp public_value?(_value), do: false

  defp invalid(reason), do: {:error, "Jido Agent action failed (#{reason})"}
end
