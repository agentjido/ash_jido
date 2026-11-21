defmodule AshJido do
  @moduledoc """
  Compiles selected Ash APIs into native Jido v3 Actions.

  Add the extension to an Ash domain and expose its code interfaces:

      defmodule MyApp.Accounts do
        use Ash.Domain, extensions: [AshJido]

        resources do
          resource MyApp.Accounts.User do
            define :register_user, action: :register
            define :get_user, action: :read, get_by: [:id]
          end
        end

        jido do
          expose :register_user
          expose :get_user
        end
      end

  AshJido generates `MyApp.Accounts.Jido.RegisterUser` and
  `MyApp.Accounts.Jido.GetUser`. Run them through Jido:

      Jido.Exec.run(
        MyApp.Accounts.Jido.RegisterUser,
        %{name: "Ada", email: "ada@example.com"},
        %{ash: %{actor: current_user, tenant: tenant}}
      )

  Each success uses a stable envelope:

      %{result: public_data, page: nil, metadata: nil}

  The Ash domain is fixed at compile time. A caller cannot replace it or set
  `authorize?: false`. Sensitive and private resource fields are not present
  in generated output.

  A resource can use `action :name` as a direct fallback when no domain code
  interface exists. AshJido also provides `AshJido.Notifier` for explicit
  Jido Signal publications and `AshJido.Persistence.Adapter` for a
  user-owned Ash persistence resource.

  Use `AshJido.Info.action_modules/1` and `AshJido.Info.descriptors/1` to
  inspect the compiled bridge.

  Use `start_agent/3` to start an Ash-backed Agent for an existing row.
  """

  @sections [AshJido.Resource.Dsl.jido_section()]

  use Spark.Dsl.Extension,
    transformers: [
      AshJido.Persistence.Transformers.DefineStore,
      AshJido.Domain.Transformers.CompileActions,
      AshJido.Resource.Transformers.GenerateJidoActions,
      AshJido.Resource.Transformers.CompilePublications
    ],
    sections: @sections

  @version Mix.Project.config()[:version]

  @doc """
  Starts a durable Agent for an existing Ash resource row.

  The Agent must declare its resource with `AshJido.State.DSL.ash/2`.
  Pass the primary key as a scalar or, for a composite key, a map of key
  fields. Pass `:tenant` in the options for an attribute-multitenant resource.
  AshJido derives the Agent ID from the row and waits for the Agent to be ready.

  For example:

      AshJido.start_agent(MyApp.Jido, MyApp.Support.CaseAgent, case_id)

  This uses the same startup path and errors as passing `row/2` as the
  `:state` option to `Jido.start_agent/3`.
  """
  @spec start_agent(module(), module(), term(), keyword()) :: {:ok, pid()} | {:error, term()}
  defdelegate start_agent(instance, agent, primary_key, opts \\ []), to: AshJido.State

  @doc """
  Builds a row reference for the `:state` option of `Jido.start_agent/3`.

  Pass a scalar primary key or a map of primary key fields. Set `:tenant`
  for an attribute-multitenant resource. The Agent DSL supplies the resource.
  """
  @spec row(term(), keyword()) :: %Jido.AgentServer.StateProvider.Source{}
  def row(primary_key, opts \\ []) do
    %Jido.AgentServer.StateProvider.Source{provider: AshJido.State, input: {primary_key, opts}}
  end

  @doc """
  Returns the version of AshJido.
  """
  def version, do: @version

  @doc false
  def explain(dsl_state, opts) do
    Spark.Dsl.Extension.explain(dsl_state, __MODULE__, nil, opts)
  end
end
