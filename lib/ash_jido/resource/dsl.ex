defmodule AshJido.Resource.Dsl do
  @moduledoc """
  DSL section definition for the jido section.
  """

  @metadata_fields [:actor, :tenant, :changes, :previous_state]
  @publish_action_types [:create, :update, :destroy, :action]
  @include_modes [:pkey_only, :all, :changes_only]

  def jido_section do
    %Spark.Dsl.Section{
      name: :jido,
      describe: """
      Configure Ash/Jido integration for this resource.
      """,
      schema: [
        signal_bus: [
          type: {:or, [:atom, :mfa]},
          required: false,
          doc: """
          The Jido.Signal.Bus server to publish resource-change signals to.
          Falls back to `config :ash_jido, :signal_bus` if not set.
          """
        ],
        signal_prefix: [
          type: :string,
          required: false,
          doc: """
          Prefix used for auto-derived signal types.
          Falls back to `config :ash_jido, :signal_prefix, \"ash\"`.
          """
        ]
      ],
      entities: [
        action_entity(),
        all_actions_entity(),
        publish_entity(),
        publish_all_entity()
      ]
    }
  end

  defp action_entity do
    %Spark.Dsl.Entity{
      name: :action,
      describe: """
      Expose an Ash action as a Jido action.

      ## Usage Examples

      Simple syntax (uses all defaults):
      ```elixir
      jido do
        action :create
        action :read
        action :update
      end
      ```

      With custom name and description:
      ```elixir
      jido do
        action :create, name: "create_user", description: "Create a new user account"
      end
      ```

      With tags for AI discovery:
      ```elixir
      jido do
        action :read, tags: ["search", "user-management", "public"]
      end
      ```
      """,
      target: AshJido.Resource.JidoAction,
      args: [:action],
      schema: [
        action: [
          type: :atom,
          required: true,
          doc: "The name of the Ash action to expose"
        ],
        name: [
          type: :string,
          doc: "Custom name for the Jido action. Defaults to smart naming: 'resource_action'"
        ],
        module_name: [
          type: :atom,
          doc: "Custom module name. Defaults to: 'Resource.Jido.ActionName'"
        ],
        description: [
          type: :string,
          doc:
            "Description for the Jido action. Inherits from Ash action description if available"
        ],
        category: [
          type: :string,
          doc: "Category for Jido discovery and tool organization"
        ],
        tags: [
          type: {:list, :string},
          default: [],
          doc: "Tags for better categorization and AI discovery. Auto-generates smart defaults"
        ],
        vsn: [
          type: :string,
          doc: "Optional semantic version identifier for generated action metadata"
        ],
        output_map?: [
          type: :boolean,
          default: true,
          doc: "Convert output structs to maps (recommended for AI tools)"
        ],
        load: [
          type: :any,
          doc: "Static Ash.Query.load statement to apply to generated read actions"
        ],
        action_parameters: [
          type: {:list, {:in, [:filter, :sort, :limit, :offset]}},
          doc:
            "Query parameters to expose for read actions. Defaults to all (filter, sort, limit, offset). Set to a subset to restrict."
        ],
        emit_signals?: [
          type: :boolean,
          default: false,
          doc: "Emit Jido signals from Ash notifications for create/update/destroy actions"
        ],
        signal_dispatch: [
          type: :any,
          doc:
            "Default dispatch configuration for emitted signals (override with context[:signal_dispatch])"
        ],
        signal_type: [
          type: :string,
          doc: "Override the emitted signal type"
        ],
        signal_source: [
          type: :string,
          doc: "Override the emitted signal source"
        ],
        telemetry?: [
          type: :boolean,
          default: false,
          doc: "Emit telemetry spans for generated action execution"
        ]
      ]
    }
  end

  defp all_actions_entity do
    %Spark.Dsl.Entity{
      name: :all_actions,
      describe: """
      Expose all Ash actions as Jido actions with smart defaults.

      This creates Jido actions for all create, read, update, destroy, and custom actions
      defined on the resource, using intelligent naming and categorization.

      ## Usage

      ```elixir
      jido do
        all_actions
        # Optionally exclude specific actions
        all_actions except: [:internal_action, :admin_only]
      end
      ```
      """,
      target: AshJido.Resource.AllActions,
      args: [],
      schema: [
        except: [
          type: {:list, :atom},
          default: [],
          doc: "List of action names to exclude from auto-generation"
        ],
        only: [
          type: {:list, :atom},
          doc: "If specified, only generate actions for these action names"
        ],
        category: [
          type: :string,
          doc:
            "Category override applied to generated actions. Defaults to ash.<action_type> when omitted"
        ],
        tags: [
          type: {:list, :string},
          default: [],
          doc: "Additional tags to add to all generated actions"
        ],
        vsn: [
          type: :string,
          doc: "Optional semantic version identifier applied to generated action metadata"
        ],
        read_load: [
          type: :any,
          doc: "Static Ash.Query.load statement applied to all auto-generated read actions"
        ],
        read_action_parameters: [
          type: {:list, {:in, [:filter, :sort, :limit, :offset]}},
          doc:
            "Query parameters to expose for auto-generated read actions. Defaults to all (filter, sort, limit, offset). Set to a subset to restrict."
        ],
        emit_signals?: [
          type: :boolean,
          default: false,
          doc:
            "Emit Jido signals from Ash notifications for generated create/update/destroy actions"
        ],
        signal_dispatch: [
          type: :any,
          doc:
            "Default dispatch configuration for emitted signals (override with context[:signal_dispatch])"
        ],
        signal_type: [
          type: :string,
          doc: "Override emitted signal type for generated actions"
        ],
        signal_source: [
          type: :string,
          doc: "Override emitted signal source for generated actions"
        ],
        telemetry?: [
          type: :boolean,
          default: false,
          doc: "Emit telemetry spans for generated action execution"
        ]
      ]
    }
  end

  defp publish_entity do
    %Spark.Dsl.Entity{
      name: :publish,
      describe: """
      Publish a Jido signal when matching Ash actions complete.

      ## Examples

          publish :create
          publish :create, "blog.post.created", include: [:id, :title]
          publish [:publish, :archive], "blog.post.updated", include: :changes_only
      """,
      target: AshJido.Publication,
      args: [:actions, {:optional, :signal_type}],
      schema: [
        actions: [
          type: {:or, [:atom, {:list, :atom}]},
          required: true,
          doc: "Action name or list of action names that trigger this publication."
        ],
        signal_type: [
          type: :string,
          required: false,
          doc:
            "Explicit signal type. If omitted, AshJido derives one as `{prefix}.{resource}.{action}`."
        ],
        include: [
          type: {:or, [{:in, @include_modes}, {:list, :atom}]},
          required: false,
          default: :pkey_only,
          doc: "Data inclusion mode for signal payloads."
        ],
        metadata: [
          type: {:list, {:in, @metadata_fields}},
          required: false,
          default: [],
          doc: "Additional metadata fields to include in `signal.extensions.jido_metadata`."
        ],
        condition: [
          type: {:fun, 1},
          required: false,
          doc: "Optional predicate function. Signal publishes only when it returns true."
        ]
      ]
    }
  end

  defp publish_all_entity do
    %Spark.Dsl.Entity{
      name: :publish_all,
      describe: """
      Publish a Jido signal for all actions of a given action type.

      ## Examples

          publish_all :update
          publish_all :destroy, "blog.post.deleted"
      """,
      target: AshJido.Resource.PublishAll,
      args: [:action_type, {:optional, :signal_type}],
      schema: [
        action_type: [
          type: {:in, @publish_action_types},
          required: true,
          doc: "Ash action type to expand into publications."
        ],
        signal_type: [
          type: :string,
          required: false,
          doc: "Explicit signal type override for generated publications."
        ],
        include: [
          type: {:or, [{:in, @include_modes}, {:list, :atom}]},
          required: false,
          default: :pkey_only,
          doc: "Data inclusion mode for signal payloads."
        ],
        metadata: [
          type: {:list, {:in, @metadata_fields}},
          required: false,
          default: [],
          doc: "Additional metadata fields to include in `signal.extensions.jido_metadata`."
        ]
      ]
    }
  end
end
