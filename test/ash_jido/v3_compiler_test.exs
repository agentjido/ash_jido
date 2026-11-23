defmodule AshJido.V3CompilerTest do
  use ExUnit.Case, async: true

  alias AshJido.Test.Domain

  test "domain exposures compile to native Jido Actions" do
    modules = AshJido.Info.action_modules(Domain)

    assert modules == [
             Domain.Jido.RegisterUser,
             Domain.Jido.GetUser,
             Domain.Jido.ListUsers,
             Domain.Jido.DoubleValue,
             Domain.Jido.LookupUsers
           ]

    assert Enum.all?(modules, &match?({:ok, %Runic.Workflow{}}, Jido.Exec.compile(&1, [])))
    assert Enum.all?(modules, &(Code.ensure_loaded?(&1) and function_exported?(&1, :validate_params, 1)))
    assert Enum.all?(modules, &function_exported?(&1, :validate_output, 1))

    descriptors = AshJido.Info.descriptors(Domain)
    assert descriptors == Enum.map(modules, & &1.__ash_jido__())
    assert Enum.map(descriptors, & &1.name) == ~w(register_user get_user list_users double_value lookup_users)
    assert Enum.all?(descriptors, &(&1.domain == Domain))
    assert Enum.all?(descriptors, &(byte_size(&1.fingerprint) == 64))
  end

  test "code-interface metadata sets cardinality and identity" do
    get = Domain.Jido.GetUser.__ash_jido__()
    list = Domain.Jido.ListUsers.__ash_jido__()
    calculation = Domain.Jido.DoubleValue.__ash_jido__()
    direct = Domain.Jido.LookupUsers.__ash_jido__()

    assert get.source == {:code_interface, Domain, :get_user}
    assert get.result_cardinality == :one
    assert get.identity == [:id]
    assert list.result_cardinality == :many
    assert calculation.action_type == :calculation
    assert direct.source == {:domain_action, Domain, :get_user}
    assert direct.ash_action == :read
  end

  test "domain declarations cannot emit the same module after a name override" do
    assert_raise ArgumentError, ~r/duplicate generated module .*Jido.GetUser/, fn ->
      defmodule ConflictingDomain do
        use Ash.Domain, validate_config_inclusion?: false, extensions: [AshJido]

        resources do
          resource AshJido.Test.User do
            define(:get_user, action: :read, get_by: [:id])
          end
        end

        jido do
          expose(:get_user, name: "fetch_user")
          action(:lookup_users, AshJido.Test.User, :read, name: "get_user")
        end
      end
    end

    refute Code.ensure_loaded?(ConflictingDomain.Jido.GetUser)
  end

  test "schemas are static Zoi schemas with explicit controls" do
    list_schema = Domain.Jido.ListUsers.schema()

    assert {:ok, %{limit: 20, filter: %{active: true}}} =
             Zoi.parse(list_schema, %{limit: 20, filter: %{active: true}})

    assert {:error, _issues} = Zoi.parse(list_schema, %{offset: 0, unknown: true})
    assert {:error, _issues} = Zoi.parse(Domain.Jido.GetUser.schema(), %{})

    assert {:ok, %{result: 2, page: nil, metadata: nil}} =
             Domain.Jido.DoubleValue.validate_output(%{result: 2, page: nil, metadata: nil})
  end

  test "resource shorthand remains available with a fixed domain" do
    modules = AshJido.Info.action_modules(AshJido.Test.User)

    assert AshJido.Test.User.Jido.Register in modules
    assert AshJido.Test.User.Jido.UpdateAge in modules
    assert AshJido.Test.User.Jido.Destroy in modules
  end

  test "run-time domain selection and authorization bypass are rejected" do
    descriptor = Domain.Jido.RegisterUser.__ash_jido__()

    assert_raise ArgumentError, ~r/domain is fixed/, fn ->
      AshJido.Context.extract_ash_opts!(%{ash: %{domain: Other.Domain}}, descriptor)
    end

    assert_raise ArgumentError, ~r/cannot disable/, fn ->
      AshJido.Context.extract_ash_opts!(%{ash: %{authorize?: false}}, descriptor)
    end

    assert_raise ArgumentError, ~r/context.ash must be a map/, fn ->
      AshJido.Context.extract_ash_opts!(%{ash: :invalid}, descriptor)
    end

    assert AshJido.Context.extract_ash_opts!(
             %{ash: %{authorize?: true, actor: %{id: "actor"}, timeout: 500}},
             descriptor
           ) == [authorize?: true, timeout: 500, actor: %{id: "actor"}, domain: Domain]
  end
end
