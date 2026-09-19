defmodule AshJidoConsumer.Accounts do
  use Ash.Domain,
    validate_config_inclusion?: false,
    extensions: [AshJido]

  resources do
    resource AshJidoConsumer.Accounts.User do
      define(:create_user, action: :create)
      define(:get_user, action: :read, get_by: [:id])
      define(:list_users, action: :read)
      define(:inspect_runtime, action: :inspect_runtime)
      define(:slow_runtime, action: :slow_runtime)
      define(:explode, action: :explode)
    end
  end

  jido do
    expose(:create_user)
    expose(:get_user)

    expose(:list_users,
      filters: [:email],
      sorts: [:name],
      pagination: [type: :offset, max_page_size: 50]
    )

    expose(:inspect_runtime)
    expose(:slow_runtime)
    expose(:explode)
  end
end
