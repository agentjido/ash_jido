defmodule AshJido.Resource.Dsl do
  @moduledoc false

  @metadata_fields [:actor, :tenant, :changes, :previous_state]
  @include_modes [:pkey_only, :all, :changes_only]

  @doc false
  @spec jido_section() :: Spark.Dsl.Section.t()
  def jido_section do
    %Spark.Dsl.Section{
      name: :jido,
      describe: "Compile selected Ash APIs into Jido v3 Actions and Signals.",
      schema: [
        signal_bus: [
          type: {:or, [:atom, :mfa]},
          required: false,
          doc: "Jido.Signal.Bus server used by Ash notifier publications."
        ]
      ],
      entities: [expose_entity(), action_entity(), publish_entity(), persistence_store_entity()]
    }
  end

  defp expose_entity do
    %Spark.Dsl.Entity{
      name: :expose,
      describe: "Expose one Ash domain code interface as a Jido Action.",
      target: AshJido.Domain.Exposure,
      args: [:interface],
      schema: [
        interface: [type: :atom, required: true, doc: "Ash code interface name."],
        name: [type: :string, doc: "Jido Action name. Defaults to the interface name."],
        module_name: [type: :atom, doc: "Generated module name."],
        description: [type: :string, doc: "Jido Action description."],
        identity: identity_schema(),
        action_parameters: action_parameters_schema(),
        private_inputs: private_inputs_schema(),
        select: select_schema(),
        load: load_schema(),
        filters: filters_schema(),
        sorts: sorts_schema(),
        loads: loads_schema(),
        pagination: pagination_schema(),
        schema_overrides: schema_overrides_schema()
      ]
    }
  end

  defp action_entity do
    %Spark.Dsl.Entity{
      name: :action,
      describe:
        "Expose an Ash action directly. On a resource, use `action :name`. On a domain, also give the resource and Ash action.",
      target: AshJido.Resource.JidoAction,
      args: [:action, {:optional, :resource}, {:optional, :ash_action}],
      schema: [
        action: [
          type: :atom,
          required: true,
          doc: "Ash action name on a resource, or public Jido name on a domain."
        ],
        resource: [type: :atom, doc: "Ash resource for a domain direct-action declaration."],
        ash_action: [type: :atom, doc: "Ash action for a domain direct-action declaration."],
        name: [type: :string, doc: "Jido Action name override."],
        module_name: [type: :atom, doc: "Generated module name."],
        description: [type: :string, doc: "Jido Action description."],
        identity: identity_schema(),
        action_parameters: action_parameters_schema(),
        private_inputs: private_inputs_schema(),
        select: select_schema(),
        load: load_schema(),
        filters: filters_schema(),
        sorts: sorts_schema(),
        loads: loads_schema(),
        pagination: pagination_schema(),
        schema_overrides: schema_overrides_schema()
      ]
    }
  end

  defp publish_entity do
    %Spark.Dsl.Entity{
      name: :publish,
      describe: "Publish one Jido Signal after matching Ash actions complete.",
      target: AshJido.Publication,
      args: [:actions, {:optional, :signal_type}],
      schema: [
        actions: [type: {:or, [:atom, {:list, :atom}]}, required: true],
        signal_type: [type: :string, required: true],
        include: [
          type: {:or, [{:in, @include_modes}, {:list, :atom}]},
          required: false,
          default: :pkey_only
        ],
        metadata: [
          type: {:list, {:in, @metadata_fields}},
          required: false,
          default: []
        ],
        condition: [type: {:fun, 1}, required: false]
      ]
    }
  end

  defp persistence_store_entity do
    %Spark.Dsl.Entity{
      name: :persistence_store,
      describe: "Mark this resource as a Jido byte persistence store.",
      target: AshJido.Persistence.Store,
      args: [],
      schema: []
    }
  end

  defp identity_schema do
    [
      type: {:or, [:atom, {:list, :atom}, {:literal, false}]},
      required: false,
      doc: "Named Ash identity, explicit identity fields, or false for no record identity."
    ]
  end

  defp action_parameters_schema do
    [type: {:list, :atom}, required: false, doc: "Explicit Ash action inputs."]
  end

  defp private_inputs_schema do
    [type: {:list, :atom}, required: false, default: [], doc: "Explicit private Ash inputs."]
  end

  defp select_schema do
    [type: {:list, :atom}, required: false, doc: "Static Ash select list."]
  end

  defp load_schema do
    [type: :any, required: false, doc: "Static Ash load statement."]
  end

  defp filters_schema do
    [type: {:list, :atom}, required: false, default: [], doc: "Allowed filter fields."]
  end

  defp sorts_schema do
    [type: {:list, :atom}, required: false, default: [], doc: "Allowed sort fields."]
  end

  defp loads_schema do
    [type: :any, required: false, default: [], doc: "Allowed run-time load statements."]
  end

  defp pagination_schema do
    [type: :keyword_list, required: false, doc: "Explicit pagination controls."]
  end

  defp schema_overrides_schema do
    [type: :map, required: false, default: %{}, doc: "Zoi schemas keyed by input name."]
  end
end
