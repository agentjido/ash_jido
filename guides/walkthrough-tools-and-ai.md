# Walkthrough: Tools and AI Integration

AshJido-generated actions are standard `Jido.Action` modules, which means they can be exported as tool definitions for agent systems.

## 1. Add Discovery Metadata to Actions

```elixir
jido do
  action :create,
    name: "create_post",
    description: "Create a new blog post",
    category: "ash.create",
    tags: ["blog", "content"],
    vsn: "1.0.0"

  action :read,
    name: "search_posts",
    description: "List posts with optional filters"
end
```

For bulk generation, `all_actions` can set metadata defaults:

```elixir
jido do
  all_actions tags: ["blog"]
  # category defaults to "ash.<action_type>" unless explicitly set
end
```

## 2. Export Generated Actions

Use `AshJido.Tools` to discover generated modules:

```elixir
# For one resource
AshJido.Tools.actions(MyApp.Blog.Post)

# For all resources in a domain
AshJido.Tools.actions(MyApp.Blog)
```

Each generated module supports metadata from `use Jido.Action`:

```elixir
MyApp.Blog.Post.Jido.Create.tags()
MyApp.Blog.Post.Jido.Create.category()
MyApp.Blog.Post.Jido.Create.vsn()
```

## 3. Export Tool Payloads for Agent Use

```elixir
tools = AshJido.Tools.tools(MyApp.Accounts.User)

# Tool payload shape includes name/description/schema/function
tool = Enum.find(tools, &(&1.name == "create_user"))

{:ok, _result} =
  tool.function.(
    %{"name" => "Agent User", "email" => "agent@example.com"},
    %{domain: MyApp.Accounts}
  )
```

This keeps integration simple: resource DSL defines behavior once, and both runtime actions and tool exports share the same generated modules.

## 4. Practical Integration Pattern

- Use AshJido DSL to define action surface area and metadata.
- Use `AshJido.Tools.tools/1` at runtime to build the tool list for your agent.
- Route tool execution through generated `run/2` functions to preserve Ash validation, policies, and data-layer behavior.
