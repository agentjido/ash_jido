defmodule AshJidoConsumer.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias AshJidoConsumer.Repo
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AshJidoConsumer.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(AshJidoConsumer.Repo, {:shared, self()})
    end

    :ok
  end
end
