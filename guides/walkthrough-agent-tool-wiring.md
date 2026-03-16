# Walkthrough: Agent Tool Wiring with AshJido

This walkthrough shows a practical, safe pattern for exporting and executing generated actions as tools.

## 1. Discover Generated Actions

Use `AshJido.Tools.actions/1` for either a single resource or an entire domain.

```elixir
# Resource-level
resource_actions = AshJido.Tools.actions(MyApp.Accounts.User)

# Domain-level
all_actions = AshJido.Tools.actions(MyApp.Accounts)
```

Use domain-level discovery when you want one unified tool catalog for an agent.

## 2. Export Tool Payloads

`AshJido.Tools.tools/1` returns tool maps with:

- `name`
- `description`
- `parameters_schema`
- `function`

```elixir
tools = AshJido.Tools.tools(MyApp.Accounts)

create_user_tool = Enum.find(tools, &(&1.name == "create_user"))
```

## 3. Safe Execution Wrapper Pattern

Wrap tool execution to normalize context handling and JSON decode behavior.

```elixir
def run_tool(tool, params, domain, base_context \\ %{}) do
  context = Map.put(base_context, :domain, domain)

  case tool.function.(params, context) do
    {:ok, json} ->
      {:ok, Jason.decode!(json)}

    {:error, json} ->
      {:error, Jason.decode!(json)}
  end
end
```

Guidelines:

1. Keep tool params as string-key maps for LLM integration paths.
2. Always inject `domain` into execution context.
3. Treat `{:ok, json}` and `{:error, json}` as structured payloads.

## 4. Metadata Strategy (`tags`, `category`, `vsn`)

Set metadata in DSL so tools are easier to route and version.

```elixir
jido do
  action :create,
    name: "create_user",
    category: "ash.accounts.write",
    tags: ["accounts", "write", "user"],
    vsn: "1.2.0"
end
```

Metadata can be read from generated modules:

```elixir
MyApp.Accounts.User.Jido.Create.category()
MyApp.Accounts.User.Jido.Create.tags()
MyApp.Accounts.User.Jido.Create.vsn()
```

This gives a stable contract for tool catalogs, capability routing, and compatibility tracking.
