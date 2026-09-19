defmodule AshJido.SerializerTest do
  use ExUnit.Case, async: true

  alias AshJido.Serializer

  test "serializes transport-safe scalar and container values" do
    assert Serializer.serialize(nil) == nil
    assert Serializer.serialize(%Decimal{coef: 123, exp: -2, sign: 1}) == "1.23"
    assert Serializer.serialize(~D[2026-09-19]) == "2026-09-19"
    assert Serializer.serialize(~T[12:13:14]) == "12:13:14"
    assert Serializer.serialize(~N[2026-09-19 12:13:14]) == "2026-09-19T12:13:14"
    assert Serializer.serialize(~U[2026-09-19 12:13:14Z]) == "2026-09-19T12:13:14Z"
    assert Serializer.serialize(MapSet.new([1])) == [1]
    assert Serializer.serialize(%URI{scheme: "https", host: "example.com"}).host == "example.com"
    assert Serializer.serialize(%{values: [1, %{two: 2}]}) == %{values: [1, %{two: 2}]}
    assert Serializer.serialize(%Ash.NotLoaded{}) == nil
    assert Serializer.serialize(%Ash.ForbiddenField{}) == nil
  end

  test "serializes only public, loaded, non-sensitive Ash fields" do
    user = %AshJido.Test.User{
      id: "id",
      name: "Ada",
      email: "ada@example.com",
      secret: "do not expose"
    }

    serialized = Serializer.serialize(user)

    assert serialized.id == "id"
    assert serialized.name == "Ada"
    refute Map.has_key?(serialized, :secret)
  end

  test "builds stable result envelopes for plain and paged values" do
    assert Serializer.envelope(%{id: 1}, %{source: :test}) == %{
             result: %{id: 1},
             page: nil,
             metadata: %{source: :test}
           }

    offset = %Ash.Page.Offset{results: [%{id: 1}], limit: 10, offset: 20, count: 31, more?: true}

    assert Serializer.envelope(offset).page == %{
             type: :offset,
             limit: 10,
             offset: 20,
             count: 31,
             more?: true
           }

    keyset = %Ash.Page.Keyset{
      results: [%{id: 1}],
      limit: 10,
      before: "before",
      after: "after",
      count: 31,
      more?: false
    }

    assert Serializer.envelope(keyset).page == %{
             type: :keyset,
             limit: 10,
             before: "before",
             after: "after",
             count: 31,
             more?: false
           }
  end
end
