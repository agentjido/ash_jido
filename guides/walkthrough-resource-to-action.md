# Walkthrough: Resource to Action

This walkthrough shows the core AshJido flow:

1. Define Ash resources.
2. Expose selected actions through the `jido` DSL.
3. Execute generated `Jido.Action` modules with runtime context.
4. Use generated actions directly in a `Jido.AI.Agent`.

## 1. Define a Domain and Resources

```elixir
defmodule MyApp.Blog do
  use Ash.Domain

  resources do
    resource MyApp.Blog.Author
    resource MyApp.Blog.Post
  end
end

defmodule MyApp.Blog.Author do
  use Ash.Resource,
    domain: MyApp.Blog,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "authors"
    repo MyApp.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name]
    end
  end
end
```

```elixir
defmodule MyApp.Blog.Post do
  use Ash.Resource,
    domain: MyApp.Blog,
    extensions: [AshJido],
    data_layer: AshPostgres.DataLayer

  postgres do
    table "posts"
    repo MyApp.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :status, :atom, default: :draft
    timestamps()
  end

  relationships do
    belongs_to :author, MyApp.Blog.Author, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title, :author_id]
    end

    update :publish do
      accept []
      change set_attribute(:status, :published)
    end
  end

  jido do
    action :create, name: "create_post"
    action :read, name: "list_posts", load: [:author]
    action :publish, name: "publish_post"
  end
end
```

## 2. Run Generated Actions

```elixir
alias MyApp.Blog.{Author, Post}

# Create related data with Ash directly
author =
  Author
  |> Ash.Changeset.for_create(:create, %{name: "Ada"}, domain: MyApp.Blog)
  |> Ash.create!(domain: MyApp.Blog)

# Execute generated Jido actions
{:ok, post} =
  Post.Jido.Create.run(
    %{title: "Ash + Jido", author_id: author.id},
    %{domain: MyApp.Blog}
  )

{:ok, posts} = Post.Jido.Read.run(%{}, %{domain: MyApp.Blog})
loaded = Enum.find(posts, &(&1[:id] == post[:id]))

# Static load from DSL is applied to read actions
loaded[:author][:name] # => "Ada"

{:ok, published} =
  Post.Jido.Publish.run(
    %{id: post[:id]},
    %{domain: MyApp.Blog}
  )

published[:status] # => :published
```

## 3. Pass Ash Context Through Runtime Context

`domain` is required. Other Ash options are optional and passed through when present:

```elixir
context = %{
  domain: MyApp.Blog,
  actor: current_user,
  tenant: "org_123",
  scope: %{actor: current_user},
  authorize?: true,
  tracer: [MyApp.Tracer],
  context: %{request_id: "req_123"},
  timeout: 15_000
}

Post.Jido.Create.run(params, context)
```

Notes:

- If `actor` is omitted, Ash can still resolve actor from `scope`.
- If `actor: nil` is explicitly set, it intentionally overrides actor from scope.

## 4. Rules to Remember

- Update and destroy generated actions require `id` in params.
- `load` is static DSL configuration for read actions only.
- `output_map?: true` (default) returns maps instead of Ash structs.

## 5. Use Generated Resource Actions in a `Jido.AI.Agent`

This is the core integration demo: generated AshJido action modules can be used directly as agent tools.

```elixir
defmodule MyApp.Blog.PostAgent do
  use Jido.AI.Agent,
    name: "post_agent",
    model: :fast,
    tools: [
      MyApp.Blog.Post.Jido.Create,
      MyApp.Blog.Post.Jido.Read,
      MyApp.Blog.Post.Jido.Publish
    ],
    tool_context: %{domain: MyApp.Blog},
    system_prompt: "You manage blog posts. Use tools for data operations."
end
```

```elixir
{:ok, pid} = Jido.AgentServer.start(agent: MyApp.Blog.PostAgent)

{:ok, answer} =
  MyApp.Blog.PostAgent.ask_sync(
    pid,
    "Create a post titled 'Hello' for author #{author_id} and then list posts.",
    tool_context: %{
      domain: MyApp.Blog,
      actor: current_user,
      tenant: "org_123"
    }
  )
```

Important:

- The agent `tools:` list should use generated module names (`MyApp.Blog.Post.Jido.*`).
- Pass `domain` in `tool_context` so AshJido actions have required context.
- Add `actor`, `tenant`, and other Ash options in `tool_context` for policy and tenancy-aware calls.
