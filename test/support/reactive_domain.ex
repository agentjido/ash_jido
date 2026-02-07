defmodule AshJido.Test.ReactiveDomain do
  @moduledoc false

  use Ash.Domain,
    validate_config_inclusion?: false

  resources do
    resource(AshJido.Test.ReactiveResource)
    resource(AshJido.Test.SelectiveResource)
  end
end
