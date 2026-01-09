# Getting Started with AshJido

AshJido bridges Ash Framework resources with Jido agents by automatically generating `Jido.Action` modules from your Ash actions. Every Ash action becomes a tool in an agent's toolbox while maintaining type safety and respecting Ash authorization policies.

> **🧪 Experimental**: This library is under active development. APIs may change without notice.

## Installation

Add `ash_jido` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_jido, "~> 0.1"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Basic Usage

Add the `AshJido` extension to your Ash resource and define which actions to expose in the `jido` section:

```elixir
defmodule MyApp.Accounts.User do
  use Ash.Resource,
    domain: MyApp.Accounts,
    extensions: [AshJido]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :email, :string, allow_nil?: false
    attribute :role, :atom, default: :user
  end

  actions do
    defaults [:read, :destroy]

    create :register do
      accept [:name, :email]
    end

    update :update_profile do
      accept [:name]
    end

    update :promote do
      accept []
      change set_attribute(:role, :admin)
    end
  end

  jido do
    action :register, name: "create_user", description: "Creates a new user account"
    action :read, name: "list_users"
    action :update_profile
    action :destroy
  end
end
```

This generates Jido.Action modules for each exposed action:

- `MyApp.Accounts.User.Jido.Register`
- `MyApp.Accounts.User.Jido.Read`
- `MyApp.Accounts.User.Jido.UpdateProfile`
- `MyApp.Accounts.User.Jido.Destroy`

## Exposing All Actions

Use `all_actions` to quickly expose all actions on a resource with smart defaults:

```elixir
jido do
  all_actions
end
```

You can filter which actions to expose:

```elixir
jido do
  # Exclude specific actions
  all_actions except: [:destroy, :internal_update]
end
```

```elixir
jido do
  # Only expose specific actions
  all_actions only: [:register, :read, :update_profile]
end
```

You can also add tags to all generated actions:

```elixir
jido do
  all_actions tags: ["user-management", "public-api"]
end
```

## Using Generated Actions

Call the generated modules using `run/2` with params and a context map. The context must include at minimum a `:domain`:

```elixir
# Create a user
{:ok, user} = MyApp.Accounts.User.Jido.Register.run(
  %{name: "John Doe", email: "john@example.com"},
  %{domain: MyApp.Accounts}
)

# List users
{:ok, %{results: users, count: count}} = MyApp.Accounts.User.Jido.Read.run(
  %{},
  %{domain: MyApp.Accounts}
)

# Update a user
{:ok, updated_user} = MyApp.Accounts.User.Jido.UpdateProfile.run(
  %{id: user.id, name: "Jane Doe"},
  %{domain: MyApp.Accounts}
)

# Delete a user
{:ok, _} = MyApp.Accounts.User.Jido.Destroy.run(
  %{id: user.id},
  %{domain: MyApp.Accounts}
)
```

### Context Options

The context map supports additional options for authorization and multi-tenancy:

```elixir
context = %{
  domain: MyApp.Accounts,    # Required: the Ash domain
  actor: current_user,       # Optional: for authorization policies
  tenant: "org_123"          # Optional: for multi-tenant apps
}

MyApp.Accounts.User.Jido.Register.run(params, context)
```

## Configuration Options

Each action in the `jido` section supports these options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | `string` | `"resource_action"` | Custom name for the Jido action |
| `module_name` | `atom` | `Resource.Jido.ActionName` | Custom module name for the generated action |
| `description` | `string` | Ash action description | Description for AI discovery and documentation |
| `tags` | `list(string)` | `[]` | Tags for categorization and AI discovery |
| `output_map?` | `boolean` | `true` | Convert output structs to maps |

### Examples

```elixir
jido do
  # Simple exposure with defaults
  action :create

  # Custom name for better AI discoverability
  action :read, name: "search_users", description: "Search for users by criteria"

  # Add tags for categorization
  action :update, tags: ["user-management", "data-modification"]

  # Custom module name
  action :promote, module_name: MyApp.Actions.PromoteUser

  # Disable output map conversion (keep Ash structs)
  action :special, output_map?: false
end
```

## Output Formats

By default (`output_map?: true`), outputs are converted to maps for easier consumption:

- **Read actions** return: `%{results: [...], count: N}`
- **Create/Update actions** return: `%{result: data}`
- **Destroy actions** return: `%{result: :ok}` or the destroyed record

Set `output_map?: false` to preserve Ash structs in the output.

## Error Handling

Ash errors are automatically converted to Jido's Splode-based error system:

| Ash Error Type | Jido Error Type |
|----------------|-----------------|
| `Ash.Error.Invalid` | `Jido.Action.Error.InvalidInputError` (validation error) |
| `Ash.Error.Forbidden` | `Jido.Action.Error.ExecutionFailureError` (with reason `:forbidden`) |
| `Ash.Error.Framework` | `Jido.Action.Error.InternalError` |
| `Ash.Error.Unknown` | `Jido.Action.Error.InternalError` |

Field-level validation errors are preserved and accessible:

```elixir
case MyApp.Accounts.User.Jido.Register.run(%{name: ""}, %{domain: MyApp.Accounts}) do
  {:ok, user} ->
    # Success
    user

  {:error, %Jido.Action.Error.InvalidInputError{} = error} ->
    # Access field-specific errors
    error.details.fields
    # => %{name: ["is required"]}
    
  {:error, %Jido.Action.Error.ExecutionFailureError{details: %{reason: :forbidden}}} ->
    # Authorization failed
    :unauthorized
end
```

## Naming Conventions

### Default Action Names

Auto-generated names follow the pattern `resource_action`:

- `User` resource with `:create` action → `"user_create"`
- `BlogPost` resource with `:publish` action → `"blog_post_publish"`

### Default Module Names

Modules are generated under the resource namespace:

- `MyApp.Accounts.User` with `:register` action → `MyApp.Accounts.User.Jido.Register`
- `MyApp.Blog.Post` with `:publish` action → `MyApp.Blog.Post.Jido.Publish`

## Action Type Categories

Actions are automatically categorized based on type:

| Ash Action Type | Category | Use Case |
|-----------------|----------|----------|
| `:create` | `data_creation` | Creating new records |
| `:read` | `data_retrieval` | Querying and listing |
| `:update` | `data_modification` | Modifying existing records |
| `:destroy` | `data_deletion` | Removing records |
| `:action` | `custom_operation` | Custom business logic |

## Complete Example

Here's a complete example with a domain, resource, and usage:

```elixir
# lib/my_app/blog/domain.ex
defmodule MyApp.Blog do
  use Ash.Domain

  resources do
    resource MyApp.Blog.Post
  end
end

# lib/my_app/blog/post.ex
defmodule MyApp.Blog.Post do
  use Ash.Resource,
    domain: MyApp.Blog,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJido]

  postgres do
    table "posts"
    repo MyApp.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :body, :string
    attribute :status, :atom, default: :draft
    timestamps()
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title, :body]
    end

    update :update do
      accept [:title, :body]
    end

    update :publish do
      accept []
      change set_attribute(:status, :published)
    end
  end

  jido do
    action :create, 
      name: "create_post",
      description: "Create a new blog post draft",
      tags: ["content-management", "authoring"]

    action :read,
      name: "list_posts",
      description: "List and search blog posts"

    action :update,
      name: "edit_post",
      tags: ["content-management"]

    action :publish,
      name: "publish_post",
      description: "Publish a draft post",
      tags: ["content-management", "publishing"]

    action :destroy,
      name: "delete_post",
      tags: ["content-management", "destructive"]
  end
end
```

Using the generated actions:

```elixir
alias MyApp.Blog.Post

# Create a post
{:ok, post} = Post.Jido.Create.run(
  %{title: "Hello World", body: "My first post"},
  %{domain: MyApp.Blog}
)

# List all posts
{:ok, %{results: posts}} = Post.Jido.Read.run(%{}, %{domain: MyApp.Blog})

# Publish the post
{:ok, published} = Post.Jido.Publish.run(
  %{id: post.id},
  %{domain: MyApp.Blog}
)
```

## Next Steps

- See [Usage Rules](../usage-rules.md) for comprehensive patterns and best practices
- Check the [API Documentation](https://hexdocs.pm/ash_jido) for detailed module docs
- Explore the [Ash Framework documentation](https://hexdocs.pm/ash) for more on defining resources and actions
