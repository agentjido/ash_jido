defmodule AshJido.Test.Domain do
  @moduledoc """
  Test domain for integration tests.
  """

  use Ash.Domain,
    validate_config_inclusion?: false,
    extensions: [AshJido]

  resources do
    resource AshJido.Test.User do
      define(:register_user, action: :register)
      define(:get_user, action: :read, get_by: [:id])
      define(:list_users, action: :read)
      define_calculation(:double_value, calculation: :double_value, args: [{:arg, :value}])
    end

    resource(AshJido.Test.Post)
    resource(AshJido.Test.CustomModules)
    resource(AshJido.Test.ProtectedResource)
    resource(AshJido.Test.MultiJidoItem)
  end

  jido do
    expose(:register_user)
    expose(:get_user)
    expose(:list_users, filters: [:email, :active], sorts: [:name], pagination: [type: :offset, max_page_size: 50])
    expose(:double_value)
  end

  # Make this domain accessible for testing
  def __using__(_opts) do
    quote do
      alias AshJido.Test.Domain
    end
  end
end
