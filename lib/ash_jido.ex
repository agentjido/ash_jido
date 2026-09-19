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
  Returns the version of AshJido.
  """
  def version, do: @version

  @doc false
  def explain(dsl_state, opts) do
    Spark.Dsl.Extension.explain(dsl_state, __MODULE__, nil, opts)
  end
end
