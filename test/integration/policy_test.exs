defmodule AshJido.PolicyTest do
  @moduledoc """
  Tests that AshJido respects Ash policies when executing actions.
  """

  use ExUnit.Case, async: false

  alias AshJido.Test.{Domain, ProtectedResource}

  defmodule WriteOnlyResource do
    use Ash.Resource,
      domain: AshJido.PolicyTest.WriteOnlyDomain,
      validate_domain_inclusion?: false,
      extensions: [AshJido],
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
    end

    actions do
      defaults([:read, :destroy])

      create :create do
        accept([:title])
      end

      update :update do
        accept([:title])
      end
    end

    policies do
      policy action_type(:read) do
        forbid_if(always())
      end

      policy action_type([:create, :update, :destroy]) do
        authorize_if(always())
      end
    end

    jido do
      action(:update, name: "update_write_only")
      action(:destroy, name: "delete_write_only")
    end
  end

  defmodule WriteOnlyDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource(WriteOnlyResource)
    end
  end

  describe "policy enforcement" do
    test "create action can bypass authorization when authorize? is false in context" do
      params = %{title: "Bypassed Policy"}
      context = %{domain: Domain, actor: nil, authorize?: false}

      result = ProtectedResource.Jido.Create.run(params, context)

      assert {:ok, resource} = result
      assert resource[:title] == "Bypassed Policy"
    end

    test "create action fails without actor when policy requires actor_present" do
      params = %{title: "Secret Document"}
      context = %{domain: Domain, actor: nil}

      result = ProtectedResource.Jido.Create.run(params, context)

      assert {:error, error} = result
      assert error.details.reason == :forbidden
    end

    test "create action succeeds with actor when policy requires actor_present" do
      actor = %{id: "user_123", name: "Test User"}
      params = %{title: "Secret Document", owner_id: actor.id}
      context = %{domain: Domain, actor: actor}

      result = ProtectedResource.Jido.Create.run(params, context)

      assert {:ok, resource} = result
      assert resource[:title] == "Secret Document"
    end

    test "create action succeeds when actor is provided via scope" do
      actor = %{id: "scope_actor", name: "Scope User"}
      params = %{title: "Scoped Secret", owner_id: actor.id}
      context = %{domain: Domain, scope: %{actor: actor}}

      result = ProtectedResource.Jido.Create.run(params, context)

      assert {:ok, resource} = result
      assert resource[:title] == "Scoped Secret"
    end

    test "explicit actor nil overrides actor provided by scope" do
      actor = %{id: "scope_actor_nil", name: "Scope Nil User"}
      params = %{title: "Scoped Secret"}
      context = %{domain: Domain, scope: %{actor: actor}, actor: nil}

      result = ProtectedResource.Jido.Create.run(params, context)

      assert {:error, error} = result
      assert error.details.reason == :forbidden
    end

    test "read action succeeds without actor when policy allows always" do
      context = %{domain: Domain, actor: nil}

      result = ProtectedResource.Jido.Read.run(%{}, context)

      assert {:ok, _resources} = result
    end

    test "destroy action fails without actor when policy requires actor_present" do
      actor = %{id: "user_123", name: "Test User"}
      create_context = %{domain: Domain, actor: actor}

      {:ok, resource} = ProtectedResource.Jido.Create.run(%{title: "To Delete"}, create_context)

      destroy_context = %{domain: Domain, actor: nil}
      result = ProtectedResource.Jido.Destroy.run(%{id: resource[:id]}, destroy_context)

      assert {:error, error} = result
      assert error.details.reason == :forbidden
    end

    test "update action does not require read policy access for lookup" do
      record = create_write_only_record!("Before")

      result =
        WriteOnlyResource.Jido.Update.run(
          %{id: record.id, title: "After"},
          %{domain: WriteOnlyDomain, actor: %{id: "actor"}}
        )

      assert {:ok, updated} = result
      assert updated[:id] == record.id
      assert updated[:title] == "After"
    end

    test "destroy action does not require read policy access for lookup" do
      record = create_write_only_record!("Delete Me")

      result =
        WriteOnlyResource.Jido.Destroy.run(
          %{id: record.id},
          %{domain: WriteOnlyDomain, actor: %{id: "actor"}}
        )

      assert {:ok, %{deleted: true}} = result
    end
  end

  defp create_write_only_record!(title) do
    WriteOnlyResource
    |> Ash.Changeset.for_create(
      :create,
      %{title: title},
      domain: WriteOnlyDomain,
      authorize?: false
    )
    |> Ash.create!(domain: WriteOnlyDomain, authorize?: false)
  end
end
