defmodule AshJidoConsumer.Accounts.User do
  use Ash.Resource,
    domain: AshJidoConsumer.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJido],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("users")
    repo(AshJidoConsumer.Repo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:email, :string, allow_nil?: false, public?: true)
    timestamps()
  end

  identities do
    identity(:unique_email, [:email])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:name, :email])
    end

    update :update do
      accept([:name])
    end

    action :inspect_runtime do
      run(fn _input, context ->
        send(self(), {
          :runtime_context,
          %{
            actor_present?: not is_nil(context.actor),
            authorize?: context.authorize?,
            tenant: context.tenant,
            trace_id: get_in(context.source_context, [:shared, :trace_id]),
            tracer_present?: not is_nil(context.tracer)
          }
        })

        :ok
      end)
    end

    action :slow_runtime do
      run(fn _input, _context ->
        Process.sleep(100)
        :ok
      end)
    end

    action :explode do
      run(fn _input, _context ->
        raise "user action boom"
      end)
    end
  end

  policies do
    policy action(:create) do
      authorize_if(actor_present())
    end

    policy action_type(:read) do
      authorize_if(always())
    end

    policy action_type(:action) do
      authorize_if(always())
    end
  end

  jido do
    action(:create,
      telemetry?: true,
      category: "ash.consumer.accounts",
      tags: ["accounts", "write"],
      vsn: "1.0.0"
    )

    action(:read, telemetry?: true)
    action(:inspect_runtime, telemetry?: true)
    action(:slow_runtime, telemetry?: true)
    action(:explode, telemetry?: true)
  end
end
