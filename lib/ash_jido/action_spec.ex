defmodule AshJido.ActionSpec do
  @moduledoc false

  defstruct [
    :resource,
    :action_name,
    :action_type,
    :config,
    :primary_key,
    :generated_module
  ]

  @type t :: %__MODULE__{
          resource: module(),
          action_name: atom(),
          action_type: atom(),
          config: AshJido.Resource.JidoAction.t(),
          primary_key: [atom()],
          generated_module: module()
        }
end
