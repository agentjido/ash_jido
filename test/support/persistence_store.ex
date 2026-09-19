defmodule AshJido.Test.PersistenceStore do
  @moduledoc false

  use Ash.Resource,
    domain: AshJido.Test.PersistenceDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshJido]

  ets do
    private?(false)
  end

  jido do
    persistence_store()
  end
end

defmodule AshJido.Test.PersistenceDomain do
  @moduledoc false

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshJido.Test.PersistenceStore)
  end
end
