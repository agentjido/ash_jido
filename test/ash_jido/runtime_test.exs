defmodule AshJido.RuntimeTest do
  use ExUnit.Case, async: false

  alias AshJido.ActionSpec
  alias AshJido.Runtime

  @moduletag :capture_log

  describe "primary key helpers" do
    test "fetches single primary keys from atom or string params" do
      assert Runtime.fetch_primary_key!(%{id: "atom-id"}, [:id], :update) == "atom-id"
      assert Runtime.fetch_primary_key!(%{"id" => "string-id"}, [:id], :destroy) == "string-id"
    end

    test "fetches composite primary keys" do
      assert Runtime.fetch_primary_key!(
               %{"account_id" => "acct", external_id: "ext"},
               [:account_id, :external_id],
               :update
             ) == %{account_id: "acct", external_id: "ext"}
    end

    test "raises with the legacy id message for missing default primary keys" do
      assert_raise ArgumentError, "Update actions require an 'id' parameter", fn ->
        Runtime.fetch_primary_key!(%{}, [:id], :update)
      end

      assert_raise ArgumentError, "Destroy actions require an 'id' parameter", fn ->
        Runtime.fetch_primary_key!(%{}, [:id], :destroy)
      end
    end

    test "drops atom and string primary key params" do
      params = %{"id" => "string-id", id: "atom-id", name: "kept"}

      assert Runtime.drop_primary_key_params(params, [:id]) == %{name: "kept"}
    end
  end

  describe "run/3" do
    test "executes read actions from an action spec" do
      AshJido.Test.User
      |> Ash.Changeset.for_create(
        :register,
        %{name: "Runtime Spec", email: "runtime@example.com", age: 31},
        domain: AshJido.Test.Domain
      )
      |> Ash.create!(domain: AshJido.Test.Domain)

      spec = %ActionSpec{
        resource: AshJido.Test.User,
        action_name: :read,
        action_type: :read,
        config: %AshJido.Resource.JidoAction{action: :read, output_map?: true},
        primary_key: [:id],
        generated_module: __MODULE__
      }

      assert {:ok, %{result: results}} =
               Runtime.run(
                 spec,
                 %{filter: %{name: "Runtime Spec"}, limit: 1},
                 %{domain: AshJido.Test.Domain}
               )

      assert [%{name: "Runtime Spec"}] = results
    end
  end
end
