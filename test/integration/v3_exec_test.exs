defmodule AshJido.V3ExecTest do
  use ExUnit.Case, async: false

  alias AshJido.Test.Domain.Jido.{DoubleValue, GetUser, RegisterUser}
  alias AshJido.Test.User.Jido.{Deactivate, Destroy, UpdateAge}

  test "create, get, update, generic action, calculation, and destroy run through Jido Exec" do
    email = "user-#{System.unique_integer([:positive])}@example.com"

    assert {:ok, %{result: user, page: nil, metadata: nil}} =
             Jido.Exec.run(RegisterUser, %{name: "Ada", email: email, age: 36}, %{})

    assert user.email == email
    refute Map.has_key?(user, :secret)

    assert {:ok, %{result: fetched}} = Jido.Exec.run(GetUser, %{id: user.id}, %{})
    assert fetched.id == user.id

    assert {:ok, %{result: updated}} =
             Jido.Exec.run(UpdateAge, %{id: user.id, age: 37}, %{})

    assert updated.age == 37

    assert {:ok, %{result: %{message: "User deactivated", reason: "test"}}} =
             Jido.Exec.run(Deactivate, %{reason: "test"}, %{})

    assert {:ok, %{result: 42, page: nil}} = Jido.Exec.run(DoubleValue, %{value: 21}, %{})

    assert {:ok, %{result: %{destroyed?: true, identity: %{id: id}}}} =
             Jido.Exec.run(Destroy, %{id: user.id}, %{})

    assert id == user.id

    assert {:error, %Jido.Action.Error.ExecutionFailureError{details: %{reason: :not_found}}} =
             Jido.Exec.run(GetUser, %{id: user.id}, %{})
  end

  test "Ash actor policy remains the authorization boundary" do
    params = %{title: "Protected", owner_id: "owner-1"}

    assert {:error, %Jido.Action.Error.ExecutionFailureError{details: %{reason: :forbidden}}} =
             Jido.Exec.run(AshJido.Test.ProtectedResource.Jido.Create, params, %{})

    assert {:ok, %{result: %{title: "Protected"}}} =
             Jido.Exec.run(
               AshJido.Test.ProtectedResource.Jido.Create,
               params,
               %{ash: %{actor: %{id: "owner-1"}}}
             )
  end

  test "errors do not expose Ash internals" do
    assert {:error, error} =
             Jido.Exec.run(RegisterUser, %{name: "Missing email"}, %{})

    inspected = inspect(error)
    refute inspected =~ "Ash.Changeset"
    refute inspected =~ "Ash.Query"
    refute Map.has_key?(error.details, :exception)
  end

  test "list reads, selected results, and missing identities use safe results" do
    email = "list-#{System.unique_integer([:positive])}@example.com"

    assert {:ok, %{result: created}} =
             Jido.Exec.run(RegisterUser, %{name: "List User", email: email}, %{})

    assert {:ok, %{result: users}} =
             Jido.Exec.run(
               AshJido.Test.Domain.Jido.ListUsers,
               %{filter: %{active: true}, sort: [%{field: :name, direction: :asc}], limit: 1},
               %{}
             )

    assert is_list(users)

    descriptor = RegisterUser.__ash_jido__()

    assert {:ok, %{result: selected}} =
             AshJido.Runtime.run(
               %{descriptor | select: [:id, :name], load: [:age]},
               %{name: "Selected", email: "selected-#{email}"},
               %{}
             )

    assert selected.name == "Selected"
    assert Map.has_key?(selected, :age)
    refute Map.has_key?(selected, :secret)

    assert {:error, %Jido.Action.Error.ExecutionFailureError{details: %{reason: :not_found}}} =
             Jido.Exec.run(UpdateAge, %{id: Ash.UUID.generate(), age: 1}, %{})

    assert {:error, %Jido.Action.Error.ExecutionFailureError{details: %{reason: :not_found}}} =
             Jido.Exec.run(Destroy, %{id: Ash.UUID.generate()}, %{})

    assert AshJido.Runtime.fetch_primary_key!(%{"id" => created.id}, [:id], :update) == created.id

    assert AshJido.Runtime.fetch_primary_key!(%{tenant: "a", slug: "b"}, [:tenant, :slug], :update) == %{
             tenant: "a",
             slug: "b"
           }

    assert_raise ArgumentError, ~r/require identity fields: id/, fn ->
      AshJido.Runtime.fetch_primary_key!(%{}, [:id], :update)
    end

    assert_raise ArgumentError, ~r/no configured identity/, fn ->
      apply(AshJido.Runtime, :fetch_primary_key!, [%{}, [], :destroy])
    end

    assert AshJido.Runtime.drop_primary_key_params(%{"id" => 2, id: 1, name: "A"}, [:id]) == %{
             name: "A"
           }
  end
end
