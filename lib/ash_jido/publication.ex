defmodule AshJido.Publication do
  @moduledoc """
  Represents a single signal publication configuration from the `jido` DSL.
  """

  defstruct [
    :actions,
    :signal_type,
    :include,
    :metadata,
    :condition,
    :__spark_metadata__
  ]

  @type include_mode :: :pkey_only | :all | :changes_only | [atom()]

  @type t :: %__MODULE__{
          actions: [atom()] | nil,
          signal_type: String.t() | nil,
          include: include_mode() | nil,
          metadata: [atom()] | nil,
          condition: (Ash.Notifier.Notification.t() -> boolean()) | nil
        }
end
