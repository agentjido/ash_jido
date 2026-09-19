defmodule AshJido.Resource.JidoAction do
  @moduledoc """
  Represents a Jido action configuration from the DSL.
  """

  defstruct [
    :action,
    :resource,
    :ash_action,
    :name,
    :module_name,
    :description,
    :identity,
    :action_parameters,
    :private_inputs,
    :select,
    :load,
    :filters,
    :sorts,
    :loads,
    :pagination,
    :schema_overrides,
    :__spark_metadata__
  ]

  @type t :: %__MODULE__{
          action: atom(),
          resource: module() | nil,
          ash_action: atom() | nil,
          name: String.t() | nil,
          module_name: atom() | nil,
          description: String.t() | nil,
          identity: atom() | [atom()] | false | nil,
          action_parameters: [atom()] | nil,
          private_inputs: [atom()] | nil,
          select: term(),
          load: term() | nil,
          filters: [atom()] | nil,
          sorts: [atom()] | nil,
          loads: term(),
          pagination: keyword() | nil,
          schema_overrides: map() | nil
        }
end
