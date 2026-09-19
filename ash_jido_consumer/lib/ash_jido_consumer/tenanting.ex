defmodule AshJidoConsumer.Tenanting do
  use Ash.Domain,
    validate_config_inclusion?: false,
    extensions: [AshJido]

  resources do
    resource AshJidoConsumer.Tenanting.Note do
      define(:create_note, action: :create)
      define(:list_notes, action: :read)
    end
  end

  jido do
    expose(:create_note)
    expose(:list_notes)
  end
end
