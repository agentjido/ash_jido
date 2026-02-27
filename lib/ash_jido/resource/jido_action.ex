defmodule AshJido.Resource.JidoAction do
  @moduledoc """
  Represents a Jido action configuration from the DSL.
  """

  defstruct [
    :action,
    :name,
    :module_name,
    :description,
    :tags,
    :load,
    :signal_dispatch,
    :signal_type,
    :signal_source,
    :__spark_metadata__,
    emit_signals?: false,
    telemetry?: false,
    output_map?: true
  ]

  @type t :: %__MODULE__{
          action: atom(),
          name: String.t() | nil,
          module_name: atom() | nil,
          description: String.t() | nil,
          tags: [String.t()] | nil,
          load: term() | nil,
          signal_dispatch: term() | nil,
          signal_type: String.t() | nil,
          signal_source: String.t() | nil,
          emit_signals?: boolean(),
          telemetry?: boolean(),
          output_map?: boolean()
        }
end
