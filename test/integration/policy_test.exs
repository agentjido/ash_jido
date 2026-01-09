defmodule AshJido.PolicyTest do
  @moduledoc """
  Tests that AshJido respects Ash policies when executing actions.
  """

  use ExUnit.Case, async: false

  alias AshJido.Test.{Domain, ProtectedResource}

  describe "policy enforcement" do
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
  end
end
