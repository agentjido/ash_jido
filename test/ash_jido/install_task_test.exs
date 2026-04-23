defmodule AshJido.InstallTaskTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.AshJido.Install.Docs

  test "installation task docs expose the expected command" do
    assert Docs.short_doc() =~ "Installs AshJido"
    assert Docs.example() == "mix igniter.install ash_jido"
    assert Docs.long_doc() =~ Docs.example()
  end

  test "installation task reports igniter metadata when available" do
    if function_exported?(Mix.Tasks.AshJido.Install, :info, 2) do
      info = Mix.Tasks.AshJido.Install.info([], nil)

      assert info.group == :jido
      assert info.example == Docs.example()
    end
  end
end
