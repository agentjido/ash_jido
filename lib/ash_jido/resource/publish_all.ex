defmodule AshJido.Resource.PublishAll do
  @moduledoc """
  Represents a `publish_all` configuration from the DSL.
  """

  defstruct [
    :action_type,
    :signal_type,
    :include,
    :metadata,
    :__spark_metadata__
  ]

  @type t :: %__MODULE__{
          action_type: :create | :update | :destroy | :action,
          signal_type: String.t() | nil,
          include: :pkey_only | :all | :changes_only | [atom()] | nil,
          metadata: [atom()] | nil
        }
end
