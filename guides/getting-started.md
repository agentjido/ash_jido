# Getting Started with AshJido

AshJido bridges Ash Framework resources with Jido agents by automatically generating `Jido.Action` modules from your Ash actions. Every Ash action becomes a tool in an agent's toolbox while maintaining type safety and respecting Ash authorization policies.

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

And apply static relationship loads to all generated read actions:

```elixir
jido do
  all_actions only: [:read], read_load: [:profile, :roles]
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

# List users (returns list of maps when output_map?: true)
{:ok, users} = MyApp.Accounts.User.Jido.Read.run(
  %{},
  %{domain: MyApp.Accounts}
)

# Update a user (requires id)
{:ok, updated_user} = MyApp.Accounts.User.Jido.UpdateProfile.run(
  %{id: user[:id], name: "Jane Doe"},
  %{domain: MyApp.Accounts}
)

# Delete a user (requires id)
{:ok, _} = MyApp.Accounts.User.Jido.Destroy.run(
  %{id: user[:id]},
  %{domain: MyApp.Accounts}
)
```

### Context Options

The context map supports additional options for authorization and multi-tenancy:

```elixir
context = %{
  domain: MyApp.Accounts,       # Required: the Ash domain
  actor: current_user,          # Optional: for authorization policies
  tenant: "org_123",            # Optional: for multi-tenant apps
  authorize?: true,             # Optional: explicit authorization mode
  tracer: [MyApp.Tracer],       # Optional: Ash tracer modules
  scope: MyApp.Scope.for(user), # Optional: Ash scope
  context: %{request_id: "1"},  # Optional: Ash action context
  timeout: 15_000,              # Optional: Ash operation timeout
  signal_dispatch: {:pid, target: self()} # Optional: override signal dispatch
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
| `category` | `string` | `nil` | Category for discovery/tool organization |
| `tags` | `list(string)` | `[]` | Tags for categorization and AI discovery |
| `vsn` | `string` | `nil` | Optional semantic version metadata |
| `output_map?` | `boolean` | `true` | Convert output structs to maps |
| `load` | `term` | `nil` | Static `Ash.Query.load/2` statement for read actions |
| `emit_signals?` | `boolean` | `false` | Emit Jido signals from Ash notifications (create/update/destroy) |
| `signal_dispatch` | `term` | `nil` | Default signal dispatch config (overridable via context) |
| `signal_type` | `string` | derived | Override emitted signal type |
| `signal_source` | `string` | derived | Override emitted signal source |
| `telemetry?` | `boolean` | `false` | Emit Jido-namespaced telemetry for generated action execution |

`all_actions` additionally supports:

- `read_load` for static read relationship loading
- `category` (default `ash.<action_type>`)
- `tags`
- `vsn`
- `emit_signals?`, `signal_dispatch`, `signal_type`, `signal_source`, and `telemetry?`

### Telemetry

Telemetry is opt-in:

```elixir
jido do
  action :create, telemetry?: true
end
```

When enabled, generated actions emit:

- `[:jido, :action, :ash_jido, :start]`
- `[:jido, :action, :ash_jido, :stop]`
- `[:jido, :action, :ash_jido, :exception]`

### Examples

```elixir
jido do
  # Simple exposure with defaults
  action :create

  # Custom name for better AI discoverability
  action :read,
    name: "search_users",
    description: "Search for users by criteria",
    load: [:profile]

  # Add tags for categorization
  action :update,
    category: "ash.update",
    tags: ["user-management", "data-modification"],
    vsn: "1.0.0"

  # Custom module name
  action :promote, module_name: MyApp.Actions.PromoteUser

  # Disable output map conversion (keep Ash structs)
  action :special, output_map?: false
end
```

## Tool Export Helpers

Use `AshJido.Tools` when integrating generated actions with tool-oriented agent systems:

```elixir
AshJido.Tools.actions(MyApp.Accounts.User)
AshJido.Tools.actions(MyApp.Accounts)
AshJido.Tools.tools(MyApp.Accounts.User)
```

## Sensor Bridge Helpers

If you use signal dispatch targets that should also feed sensor runtimes, use `AshJido.SensorDispatchBridge`:

```elixir
AshJido.SensorDispatchBridge.forward(signal_or_message, sensor_runtime)
AshJido.SensorDispatchBridge.forward_many(messages, sensor_runtime)
AshJido.SensorDispatchBridge.forward_or_ignore(message, sensor_runtime)
```

## Output Formats

By default (`output_map?: true`), Ash structs are converted to plain maps for easier consumption by agents and JSON serialization.

Set `output_map?: false` to preserve the original Ash resource structs in the output.

## Policy Enforcement

AshJido respects Ash authorization policies. When you define policies on your resources, they are automatically enforced when actions are executed through the generated Jido modules.

```elixir
defmodule MyApp.Accounts.SecureDocument do
  use Ash.Resource,
    domain: MyApp.Accounts,
    extensions: [AshJido],
    authorizers: [Ash.Policy.Authorizer]

  policies do
    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:read) do
      authorize_if always()
    end
  end

  jido do
    action :create
    action :read
  end
end
```

When calling actions, pass the `actor` in the context:

```elixir
# This will fail with :forbidden - no actor provided
{:error, error} = SecureDocument.Jido.Create.run(
  %{title: "Secret"},
  %{domain: MyApp.Accounts, actor: nil}
)
error.details.reason  # => :forbidden

# This succeeds - actor is present
{:ok, doc} = SecureDocument.Jido.Create.run(
  %{title: "Secret"},
  %{domain: MyApp.Accounts, actor: current_user}
)
```

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

Auto-generated names follow verb-first patterns:

- `:create` → `"create_<resource>"` (e.g. `"create_user"`)
- `:read` with name `:read` → `"list_<resources>"` (e.g. `"list_users"`)
- `:read` with name `:by_id` → `"get_<resource>_by_id"` (e.g. `"get_user_by_id"`)
- `:update` → `"update_<resource>"` (e.g. `"update_user"`)
- `:destroy` → `"delete_<resource>"` (e.g. `"delete_user"`)
- custom `:action` → `"<resource>_<action_name>"` or `"<verb>_<resource>"` for common verbs

### Default Module Names

Modules are generated under the resource namespace:

- `MyApp.Accounts.User` with `:register` action → `MyApp.Accounts.User.Jido.Register`
- `MyApp.Blog.Post` with `:publish` action → `MyApp.Blog.Post.Jido.Publish`

## Action Types

Each Ash action type maps to corresponding behavior:

| Ash Action Type | Behavior |
|-----------------|----------|
| `:create` | Creates a new record via `Ash.create!` |
| `:read` | Queries records via `Ash.read!` |
| `:update` | Updates a record (requires `id` param) via `Ash.update!` |
| `:destroy` | Deletes a record (requires `id` param) via `Ash.destroy!` |
| `:action` | Runs custom logic via `Ash.run_action!` |

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
