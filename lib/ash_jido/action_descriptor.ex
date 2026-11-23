defmodule AshJido.ActionDescriptor do
  @moduledoc """
  Static description of one Ash action exposed as a Jido Action.

  AshJido builds this value at compile time. Generated Action modules expose it
  through `__ash_jido__/0`.
  """

  @enforce_keys [
    :id,
    :name,
    :module,
    :domain,
    :resource,
    :ash_action,
    :action_type,
    :input_schema,
    :output_schema,
    :fingerprint
  ]

  defstruct [
    :id,
    :name,
    :module,
    :domain,
    :resource,
    :ash_action,
    :action_type,
    :source,
    :input_schema,
    :output_schema,
    :result_cardinality,
    :identity,
    :select,
    :load,
    :fingerprint,
    :config,
    primary_key: []
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          module: module(),
          domain: module(),
          resource: module(),
          ash_action: atom(),
          action_type: atom(),
          source: term(),
          input_schema: Zoi.schema(),
          output_schema: Zoi.schema(),
          result_cardinality: :one | :many | :value,
          identity: atom() | [atom()] | nil,
          select: term(),
          load: term(),
          fingerprint: String.t(),
          config: struct() | map(),
          primary_key: [atom()]
        }

  @doc false
  @spec new!(map()) :: t()
  def new!(attrs) do
    fingerprint =
      attrs
      |> Map.update!(:config, &semantic_config/1)
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    struct!(__MODULE__, Map.put(attrs, :fingerprint, fingerprint))
  end

  defp semantic_config(%_{} = config),
    do: config |> Map.from_struct() |> Map.drop([:__spark_metadata__])

  defp semantic_config(config), do: config
end
