# Walkthrough: Policy, Scope, and Authorization Context

This walkthrough focuses on policy-aware execution with generated AshJido actions.

## 1. Context: Required vs Optional

Generated actions always require `domain` in runtime context. All other keys are optional passthroughs.

```elixir
context = %{
  domain: MyApp.Accounts,      # required
  actor: current_user,         # optional
  tenant: "org_123",          # optional
  scope: %{actor: current_user}, # optional
  authorize?: true,            # optional
  tracer: [MyApp.Tracer],      # optional
  context: %{request_id: "r1"}, # optional
  timeout: 15_000              # optional
}
```

## 2. Actor Resolution and Override Rules

Given policy-protected actions, actor resolution follows these practical rules:

1. If `actor` is present in context, that value is used.
2. If `actor` is omitted, Ash can resolve actor from `scope`.
3. If `actor: nil` is explicitly set, it intentionally clears any actor from scope.

```elixir
# actor from scope
{:ok, _doc} =
  MyApp.Accounts.SecureDocument.Jido.Create.run(
    %{title: "Scoped"},
    %{domain: MyApp.Accounts, scope: %{actor: %{id: "u1"}}}
  )

# explicit nil overrides scope actor
{:error, error} =
  MyApp.Accounts.SecureDocument.Jido.Create.run(
    %{title: "Denied"},
    %{domain: MyApp.Accounts, scope: %{actor: %{id: "u1"}}, actor: nil}
  )

error.details.reason # => :forbidden
```

## 3. `authorize?: false` and Safe Usage

`authorize?: false` is forwarded to Ash and can bypass policy checks for the call. Use this sparingly, typically in trusted internal jobs, migrations, or backfills.

```elixir
{:ok, _doc} =
  MyApp.Accounts.SecureDocument.Jido.Create.run(
    %{title: "Internal backfill"},
    %{domain: MyApp.Accounts, actor: nil, authorize?: false}
  )
```

Recommendation: keep default authorization behavior for user-facing flows and require explicit actor context.

## 4. Tenant + Scope Patterns

Tenant context is forwarded to Ash and available in runtime actions.

```elixir
{:ok, note} =
  MyApp.Tenanting.Note.Jido.Create.run(
    %{body: "Tenant note"},
    %{domain: MyApp.Tenanting, tenant: "tenant_a", scope: %{actor: %{id: "u1"}}}
  )

note[:tenant_id] # => "tenant_a"
```

## 5. Forbidden Troubleshooting Matrix

| Symptom | Likely Cause | Fix |
|---|---|---|
| `:forbidden` on create/update/destroy | Missing actor for `actor_present()` policy | Pass `actor` or `scope: %{actor: ...}` |
| `:forbidden` with `scope` present | `actor: nil` explicitly set | Remove explicit `actor: nil` unless intentionally clearing actor |
| Request unexpectedly bypasses policies | `authorize?: false` set in context | Remove flag for user-facing paths |
| Tenant data missing or cross-tenant reads | `tenant` omitted or incorrect | Pass correct `tenant` in context for all relevant calls |
