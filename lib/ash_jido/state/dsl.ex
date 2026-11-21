defmodule AshJido.State.DSL do
  @moduledoc "Declares an Ash resource as the source of a Jido Agent's state."

  @doc "Infers the state schema and configures the row binding."
  defmacro ash(resource, options) do
    if Macro.Env.lookup_import(__CALLER__, {:state_provider, 2}) == [] do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description: "ash must be declared inside state do"
    end

    quote do
      require unquote(resource)
      require Jido.Agent.DSL.State
      Jido.Agent.DSL.State.state_provider(AshJido.State, {unquote(resource), unquote(options)})
    end
  end
end
