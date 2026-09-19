# Jido Flow composition

AshJido generates normal Jido Actions. A `Jido.Flow` step can call a generated Action without an adapter or AshJido-specific Flow runtime.

## Sequential work

```elixir
alias Jido.Flow.Builder

{:ok, flow} =
  Builder.new(name: "register_and_fetch")
  |> Builder.step("register", MyApp.Accounts.Jido.RegisterUser, %{
    name: Builder.input(:name),
    email: Builder.input(:email)
  })
  |> Builder.step("fetch", MyApp.Accounts.Jido.GetUser, %{
    id: Builder.result("register", [:result, :id])
  })
  |> Builder.output(Builder.result("fetch"))
  |> Builder.build()

{:ok, %{result: user}} =
  Jido.Exec.run(
    flow,
    %{name: "Ada", email: "ada@example.com"},
    %{ash: %{actor: current_user}}
  )
```

The generated Action result envelope is part of the Flow contract. In this example, the second step reads the ID at `[:result, :id]`.

## Independent work

Steps without data or control dependencies can run in parallel:

```elixir
{:ok, flow} =
  Builder.new(name: "parallel_scores")
  |> Builder.step("left", MyApp.Accounts.Jido.ScoreUser, %{
    value: Builder.input(:left)
  })
  |> Builder.step("right", MyApp.Accounts.Jido.ScoreUser, %{
    value: Builder.input(:right)
  })
  |> Builder.output(%{
    left: Builder.result("left", [:result]),
    right: Builder.result("right", [:result])
  })
  |> Builder.build()

Jido.Exec.run(flow, %{left: 3, right: 5}, context, max_concurrency: 2)
```

## Context

Flow passes its execution context to each generated Action. Put Ash options in `context.ash`:

```elixir
context = %{
  ash: %{
    actor: current_user,
    tenant: tenant,
    scope: scope,
    context: %{request_id: request_id}
  }
}
```

The domain is already fixed in each descriptor. A Flow cannot change it.

## Failure and transaction rules

Each generated Action calls Ash through its normal API. Therefore:

- Ash authorization and field policies apply to each step.
- Each step has its own Ash transaction boundary.
- A later Flow failure does not roll back an earlier successful step.
- Use an Ash action to own work that must be in one transaction.
- Use explicit Jido Flow compensation for multi-step work that can be reversed.
- Jido controls Flow scheduling, cancellation, timeouts, and partial failures.

Do not put database transaction state in Jido context or Agent state.

## Agent use

An Agent can use the same generated modules as Actions or call a Flow that contains them. Keep portable business data in Agent state. Keep the Ash actor, tenant, and request data in execution context unless the application explicitly needs them in a checkpoint.
