defmodule AshJido.Test.SampleExtractionResult do
  @moduledoc """
  A sample Ash TypedStruct for testing typed_struct_to_schema/1.
  """

  use Ash.TypedStruct

  typed_struct do
    field(:name, :string, allow_nil?: false, description: "The name")
    field(:age, :integer, allow_nil?: true, description: "The age")
    field(:active, :boolean, allow_nil?: true)
    field(:score, :decimal, allow_nil?: true, description: "Score value")

    field(:category, :atom,
      allow_nil?: false,
      constraints: [one_of: [:a, :b, :c]],
      description: "The category"
    )

    field(:tags, {:array, :string}, allow_nil?: true, description: "List of tags")
    field(:start_date, :date, allow_nil?: true, description: "Start date")
  end
end
