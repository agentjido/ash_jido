defmodule AshJido.Resource.AllActions do
  @moduledoc """
  Represents a configuration to expose all Ash actions as Jido actions.
  """

  defstruct [
    :except,
    :only,
    :tags,
    :read_load,
    :__spark_metadata__
  ]

  @type t :: %__MODULE__{
          except: [atom()] | nil,
          only: [atom()] | nil,
          tags: [String.t()] | nil,
          read_load: term() | nil
        }
end
