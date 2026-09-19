defmodule AshJidoConsumer.V3IntegrationTest do
  use AshJidoConsumer.DataCase, async: false

  alias AshJidoConsumer.Accounts
  alias AshJidoConsumer.Content
  alias AshJidoConsumer.Content.Author
  alias AshJidoConsumer.Content.Post
  alias AshJidoConsumer.Tenanting
  alias Jido.Flow.Builder

  setup do
    start_supervised!({Jido.Signal.Bus, name: :ash_jido_consumer_bus})

    assert {:ok, _subscription} =
             Jido.Signal.Bus.subscribe(:ash_jido_consumer_bus, "**", target: self())

    :ok
  end

  test "domain Actions use AshPostgres and keep Ash authorization" do
    params = %{name: "Ada", email: unique_email("ada")}

    assert {:error, %Jido.Action.Error.ExecutionFailureError{details: %{reason: :forbidden}}} =
             Jido.Exec.run(Accounts.Jido.CreateUser, params, %{})

    context = %{ash: %{actor: %{id: "actor-1"}}}

    assert {:ok, %{result: created, page: nil, metadata: nil}} =
             Jido.Exec.run(Accounts.Jido.CreateUser, params, context)

    assert created.name == "Ada"

    assert {:ok, %{result: fetched}} =
             Jido.Exec.run(Accounts.Jido.GetUser, %{id: created.id}, context)

    assert fetched.id == created.id

    assert {:ok, %{result: users}} =
             Jido.Exec.run(
               Accounts.Jido.ListUsers,
               %{filter: %{email: params.email}, sort: [%{field: :name, direction: :asc}]},
               context
             )

    assert Enum.map(users, & &1.id) == [created.id]
  end

  test "generated Actions compose in a native Jido Flow" do
    flow =
      Builder.new(name: "consumer_create_and_fetch")
      |> Builder.step("create", Accounts.Jido.CreateUser, %{
        name: Builder.input(:name),
        email: Builder.input(:email)
      })
      |> Builder.step("fetch", Accounts.Jido.GetUser, %{
        id: Builder.result("create", [:result, :id])
      })
      |> Builder.output(Builder.result("fetch"))
      |> then(fn builder ->
        assert {:ok, flow} = Builder.build(builder)
        flow
      end)

    email = unique_email("flow")

    assert {:ok, %{result: %{email: ^email}}} =
             Jido.Exec.run(flow, %{name: "Flow User", email: email}, %{
               ash: %{actor: %{id: "actor-2"}}
             })
  end

  test "resource fallback loads relationships and publishes one safe signal" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{name: "Grace"}, domain: Content)
      |> Ash.create!(domain: Content)

    context = %{ash: %{actor: %{id: "actor-3"}}}

    assert {:ok, %{result: post}} =
             Jido.Exec.run(
               Post.Jido.Create,
               %{title: "Loaded Post", author_id: author.id},
               context
             )

    assert_receive {:signal,
                    %Jido.Signal{type: "ash_jido_consumer.content.post.created"} = signal}

    assert signal.data.id == post.id
    assert signal.data.title == "Loaded Post"
    assert signal.data.ash_jido.actor_id == "actor-3"
    refute_receive {:signal, _signal}, 100

    assert {:ok, %{result: posts}} = Jido.Exec.run(Post.Jido.Read, %{}, context)
    loaded = Enum.find(posts, &(&1.id == post.id))
    assert loaded.author.id == author.id
    assert loaded.author.name == "Grace"
  end

  test "namespaced context applies Ash multitenancy" do
    assert {:ok, %{result: note_a}} =
             Jido.Exec.run(
               Tenanting.Jido.CreateNote,
               %{body: "Tenant A"},
               %{ash: %{tenant: "tenant-a"}}
             )

    assert {:ok, %{result: note_b}} =
             Jido.Exec.run(
               Tenanting.Jido.CreateNote,
               %{body: "Tenant B"},
               %{ash: %{tenant: "tenant-b"}}
             )

    assert note_a.tenant_id == "tenant-a"
    assert note_b.tenant_id == "tenant-b"

    assert {:ok, %{result: tenant_a_notes}} =
             Jido.Exec.run(Tenanting.Jido.ListNotes, %{}, %{ash: %{tenant: "tenant-a"}})

    assert Enum.map(tenant_a_notes, & &1.body) == ["Tenant A"]
  end

  test "database errors are redacted" do
    params = %{name: "Unique", email: unique_email("unique")}
    context = %{ash: %{actor: %{id: "actor-4"}}}

    assert {:ok, _output} = Jido.Exec.run(Accounts.Jido.CreateUser, params, context)
    assert {:error, error} = Jido.Exec.run(Accounts.Jido.CreateUser, params, context)

    refute inspect(error) =~ "Ash.Changeset"
    refute inspect(error) =~ params.email
  end

  defp unique_email(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}@example.com"
  end
end
