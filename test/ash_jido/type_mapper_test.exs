defmodule AshJido.TypeMapperTest do
  use ExUnit.Case, async: true

  alias AshJido.TypeMapper

  defmodule Status do
    use Ash.Type.Enum, values: [:open, :closed]
  end

  defmodule ShortName do
    use Ash.Type.NewType, subtype_of: :string, constraints: [min_length: 2, max_length: 8]
  end

  test "maps scalar, enum, newtype, array, and typed map constraints" do
    assert {:ok, 3} = Zoi.parse(TypeMapper.to_zoi!(:integer), 3)
    assert {:ok, :open} = Zoi.parse(TypeMapper.to_zoi!(Status), :open)
    assert {:ok, "open"} = Zoi.parse(TypeMapper.to_zoi!(Status), "open")
    assert {:error, _issues} = Zoi.parse(TypeMapper.to_zoi!(ShortName), "x")

    array = TypeMapper.to_zoi!({:array, :integer}, %{allow_nil?: false})
    assert {:ok, [1, 2]} = Zoi.parse(array, [1, 2])

    map =
      TypeMapper.to_zoi!(:map, %{
        allow_nil?: false,
        constraints: [fields: [name: [type: :string, allow_nil?: false]]]
      })

    assert {:ok, %{name: "Ada"}} = Zoi.parse(map, %{name: "Ada"})
  end

  test "unsupported custom types need an explicit schema" do
    assert_raise ArgumentError, ~r/schema override/, fn ->
      TypeMapper.to_zoi!(__MODULE__)
    end

    override = Zoi.string()
    assert {:ok, "value"} = TypeMapper.to_zoi!(__MODULE__, %{}, schema_override: override) |> Zoi.parse("value")
  end
end
