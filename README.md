# AshJido

An Ash Framework extension that bridges Ash resources with the Jido agent framework. AshJido automatically converts Ash actions into Jido tools, making every Ash action available in an agent's toolbox.

## Quick Start

Add AshJido to your Ash resource:

```elixir
defmodule MyApp.User do
  use Ash.Resource,
    extensions: [AshJido]

  actions do
    default_accept_all :create, :read, :update, :destroy
  end

  jido do
    # Simple usage - expose actions with defaults
    action :create
    action :read
    
    # Advanced usage - customize the action
    action :update, 
      name: "update_user",
      description: "Update a user's information"
  end
end
```

This creates Jido.Action modules that can be used by Jido agents to interact with your Ash resources.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ash_jido` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_jido, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/ash_jido>.

