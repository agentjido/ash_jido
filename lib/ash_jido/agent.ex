defmodule AshJido.Agent do
  @moduledoc """
  Exposes selected operations on one Jido Agent type as Ash generic actions.

  Configure the Agent module and Jido instance in the `jido_agent` section.
  Use explicit lists for lifecycle operations, named routes, and state fields.
  Ash policies apply to the generated actions.
  """

  @section %Spark.Dsl.Section{
    name: :jido_agent,
    schema: [
      agent: [type: :atom, required: true, doc: "The Jido Agent module."],
      instance: [type: :atom, required: true, doc: "The Jido instance name."],
      expose_lifecycle: [
        type: {:list, :atom},
        default: [],
        doc: "The lifecycle operations to expose as actions."
      ],
      expose_routes: [
        type: {:list, :atom},
        default: [],
        doc: "The exact Agent route aliases to expose as actions."
      ],
      expose_state: [
        type: {:list, :atom},
        default: [],
        doc: "The domain state fields to include in the inspect action."
      ],
      route_arguments: [
        type: :keyword_list,
        default: [],
        doc: "Ash argument definitions keyed by route alias."
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@section],
    transformers: [AshJido.Agent.CompileActions]
end
