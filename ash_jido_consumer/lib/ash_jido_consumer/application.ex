defmodule AshJidoConsumer.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AshJidoConsumer.Repo
    ]

    opts = [strategy: :one_for_one, name: AshJidoConsumer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
