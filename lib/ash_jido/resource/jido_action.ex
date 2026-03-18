defmodule AshJido.Resource.JidoAction do
  @moduledoc """
  Represents a Jido action configuration from the DSL.
  """

  defstruct [
    :action,
    :name,
    :module_name,
    :description,
    :category,
    :tags,
    :vsn,
    :load,
    :max_page_size,
    :signal_dispatch,
    :signal_type,
    :signal_source,
    :__spark_metadata__,
    emit_signals?: false,
    telemetry?: false,
    output_map?: true,
    query_params?: true
  ]

  @type t :: %__MODULE__{
          action: atom(),
          name: String.t() | nil,
          module_name: atom() | nil,
          description: String.t() | nil,
          category: String.t() | nil,
          tags: [String.t()] | nil,
          vsn: String.t() | nil,
          load: term() | nil,
          max_page_size: pos_integer() | nil,
          signal_dispatch: term() | nil,
          signal_type: String.t() | nil,
          signal_source: String.t() | nil,
          emit_signals?: boolean(),
          telemetry?: boolean(),
          output_map?: boolean(),
          query_params?: boolean()
        }
end
