defmodule AshJido.Resource.AllActions do
  @moduledoc """
  Represents a configuration to expose all Ash actions as Jido actions.
  """

  defstruct [
    :except,
    :only,
    :category,
    :tags,
    :vsn,
    :read_load,
    :read_max_page_size,
    :signal_dispatch,
    :signal_type,
    :signal_source,
    :__spark_metadata__,
    emit_signals?: false,
    telemetry?: false,
    read_query_params?: true
  ]

  @type t :: %__MODULE__{
          except: [atom()] | nil,
          only: [atom()] | nil,
          category: String.t() | nil,
          tags: [String.t()] | nil,
          vsn: String.t() | nil,
          read_load: term() | nil,
          read_max_page_size: pos_integer() | nil,
          signal_dispatch: term() | nil,
          signal_type: String.t() | nil,
          signal_source: String.t() | nil,
          emit_signals?: boolean(),
          telemetry?: boolean(),
          read_query_params?: boolean()
        }
end
