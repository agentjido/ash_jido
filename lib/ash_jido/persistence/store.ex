defmodule AshJido.Persistence.Store do
  @moduledoc false

  defstruct [:__spark_metadata__]

  @type t :: %__MODULE__{__spark_metadata__: term()}
end
