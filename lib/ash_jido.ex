defmodule AshJido do
  @moduledoc """
  Bridge Ash Framework resources with Jido agents.

  Generates `Jido.Action` modules from Ash actions at compile time, enabling
  Ash actions to be called as AI tools while maintaining type safety and Ash policies.

  ## Usage

      defmodule MyApp.Accounts.User do
        use Ash.Resource,
          domain: MyApp.Accounts,
          extensions: [AshJido]

        actions do
          create :register
          read :by_id
        end

        jido do
          action :register
          action :by_id, name: "get_user"
        end
      end

  Generated modules can be called with `run/2`:

      {:ok, user} = MyApp.Accounts.User.Jido.Register.run(
        %{name: "John"},
        %{domain: MyApp.Accounts, actor: current_user}
      )

  ## Context

  The context map **requires** a `:domain` key. An `ArgumentError` is raised if missing.

      context = %{
        domain: MyApp.Accounts,       # REQUIRED
        actor: current_user,          # optional: for authorization
        tenant: "org_123",            # optional: for multi-tenancy
        authorize?: true,             # optional: explicit authorization mode
        tracer: [MyApp.Tracer],       # optional: Ash tracer modules
        scope: MyApp.Scope.for(user), # optional: Ash scope
        context: %{request_id: "1"},  # optional: Ash action context
        timeout: 15_000,              # optional: Ash operation timeout
        signal_dispatch: {:pid, target: self()} # optional: override signal dispatch
      }

  ## DSL: Individual Actions

      jido do
        action :create
        action :read, name: "list_users", description: "List all users", load: [:profile]
        action :update, tags: ["user-management"]
        action :special, output_map?: false
      end

  ## DSL: Bulk Exposure

      jido do
        all_actions
        all_actions except: [:destroy]
        all_actions only: [:create, :read]
        all_actions tags: ["public-api"]
        all_actions only: [:read], read_load: [:profile]
      end

  ## Action Options

  - `name` - Custom Jido action name (default: auto-generated, e.g. `"create_user"`)
  - `module_name` - Custom module name (default: `Resource.Jido.ActionName`)
  - `description` - Action description (default: from Ash action)
  - `tags` - List of tags for categorization (default: `[]`)
  - `output_map?` - Convert output structs to maps (default: `true`)
  - `load` - Static `Ash.Query.load/2` statement for read actions (default: `nil`)
  - `emit_signals?` - Emit Jido signals from Ash notifications on create/update/destroy (default: `false`)
  - `signal_dispatch` - Default dispatch configuration for emitted signals (default: `nil`)
  - `signal_type` - Override emitted signal type (default: derived)
  - `signal_source` - Override emitted signal source (default: derived)

  ## Default Naming

  When `name` is not provided:

  - `:create` → `"create_<resource>"` (e.g. `"create_user"`)
  - `:read` with name `:read` → `"list_<resources>"` (e.g. `"list_users"`)
  - `:read` with name `:by_id` → `"get_<resource>_by_id"`
  - `:update` → `"update_<resource>"`
  - `:destroy` → `"delete_<resource>"`
  - custom `:action` → `"<resource>_<action_name>"`

  ## See Also

  - [Getting Started Guide](guides/getting-started.md)
  - [Usage Rules](usage-rules.md)
  """

  @sections [AshJido.Resource.Dsl.jido_section()]

  use Spark.Dsl.Extension,
    transformers: [AshJido.Resource.Transformers.GenerateJidoActions],
    sections: @sections

  @version Mix.Project.config()[:version]

  @doc """
  Returns the version of AshJido.
  """
  def version, do: @version

  @doc false
  def explain(dsl_state, opts) do
    Spark.Dsl.Extension.explain(dsl_state, __MODULE__, nil, opts)
  end
end
