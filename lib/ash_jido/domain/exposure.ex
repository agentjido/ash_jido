defmodule AshJido.Domain.Exposure do
  @moduledoc false

  defstruct [
    :interface,
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
          interface: atom(),
          name: String.t() | nil,
          module_name: module() | nil,
          description: String.t() | nil,
          identity: atom() | [atom()] | false | nil,
          action_parameters: [atom()] | nil,
          private_inputs: [atom()] | nil,
          select: term(),
          load: term(),
          filters: [atom()] | nil,
          sorts: [atom()] | nil,
          loads: term(),
          pagination: keyword() | nil,
          schema_overrides: map() | nil
        }
end
