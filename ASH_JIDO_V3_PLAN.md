# AshJido Plan for Jido v3

Status: Implemented beta baseline  
Working branch: `release/v3`  
Baseline: AshJido `main` at `6f214d7`  
Package version: `3.0.0-beta.1`  
Dependency source: published Hex packages only

## 1. Purpose

AshJido must be a small, reliable bridge between Ash and Jido v3.

It must compile selected Ash interfaces and actions into standard Jido Actions. Those Actions must work without a separate runtime in Jido Exec, Jido Flow, Jido Agents, and Jido AI.

The package must use Spark DSLs for configuration. It must keep Ash as the owner of application data and business rules.

## 2. Goals

- Generate native Jido v3 Actions from selected Ash APIs.
- Use one compile-time descriptor as the source for schemas, modules, documentation, and discovery.
- Prefer Ash code interfaces as the public action catalog.
- Support normal Jido Flow composition without a second Flow runtime.
- Add a correct Jido persistence adapter backed by a user-owned Ash resource.
- Keep DSL names and behavior close to AshAi where the concepts are the same.
- Preserve Ash authorization, tenancy, validation, changes, hooks, and transaction behavior.
- Produce safe and stable input, output, and error contracts.
- Reject unsupported or unsafe configurations at compile time.
- Keep the package small enough to understand and test as one unit.

## 3. Non-goals

- AshJido will not replace Ash domains, resources, actions, or policies.
- AshJido will not implement another Action or Flow runtime.
- AshJido will not provide durable workflow execution or claim Saga guarantees.
- AshJido will not create cross-step database transactions for Jido Flow.
- AshJido will not decode or modify Jido persistence checkpoint bytes.
- AshJido will not depend on AshAi or use AshAi internal modules.
- AshJido will not automatically expose every public Ash action.
- AshJido will not expose raw Ash queries, changesets, exceptions, or private fields.
- AshJido will not provide one persistence implementation for all Ash data layers in the first release.

## 4. Ownership boundaries

| Area | Owner |
| --- | --- |
| Resources, actions, policies, tenants, validations, and application transactions | Ash |
| Generated action descriptors, Jido Action modules, safe serialization, and bridge errors | AshJido |
| Actions, Exec, Flow execution, and step semantics | Jido Action |
| Agents, routes, lifecycle, checkpoint coordination, and persistence ownership | Jido |
| AI profiles and Jido Action to model-tool conversion | Jido AI |
| Direct Ash tools for LLMs, ReqLLM, MCP, and vectorization | AshAi |
| Database migrations, external-effect deduplication, outbox policy, and retention | Host application |

## 5. Main architecture decisions

### 5.1 One package

Keep the work in `ash_jido`. Do not split Flow, persistence, or signal support into separate packages at the start.

### 5.2 One descriptor

Use `%AshJido.ActionDescriptor{}` as the internal representation of each generated Action.

The descriptor drives:

- Generated module code.
- Input and output schemas.
- Runtime execution.
- Documentation.
- Discovery through `AshJido.Info`.
- Module ownership and fingerprints.
- Future compatibility checks with AshAi.

### 5.3 Native Jido artifacts

Generated modules use the Jido v3 Action API. They are normal Jido Actions. Flow, Exec, Agent routes, and Jido AI must use them without an AshJido-specific execution path.

### 5.4 Compile-time domain binding

Every descriptor binds one Ash domain at compile time. Callers cannot select or replace the domain at run time.

### 5.5 Stable public contracts

Every generated Action has a static Zoi input schema and output schema. Results use one stable envelope. Errors use a small public error vocabulary.

### 5.6 Jido v3 only

The `release/v3` branch targets Jido v3. It does not contain a compatibility layer for Jido 2.

## 6. Proposed module layout

```text
AshJido
AshJido.ActionDescriptor
AshJido.Generator
AshJido.Schema
AshJido.TypeMapper
AshJido.Runtime
AshJido.Serializer
AshJido.Error
AshJido.Info

AshJido.Resource.Dsl
AshJido.Domain.Exposure
AshJido.Domain.Transformers.CompileActions
AshJido.Resource.Transformers.GenerateJidoActions

AshJido.Persistence.Adapter
AshJido.Persistence.Store
AshJido.Persistence.StoreInfo
AshJido.Persistence.Transformers.DefineStore

AshJido.Notifier
AshJido.Publication
AshJido.SignalFactory
```

Do not add these modules in the first implementation:

- `AshJido.Flow`
- `AshJido.Tools`
- `AshJido.SensorDispatchBridge`
- An AshJido plugin runtime
- A generic persistence data-layer driver

## 7. DSL design

### 7.1 Domain DSL is canonical

The Ash domain is the canonical action catalog. This makes domain binding explicit and gives one place to validate names and collisions.

Ash code interfaces are the preferred source because they already define the public API shape.

```elixir
defmodule MyApp.Accounts do
  use Ash.Domain, extensions: [AshJido]

  resources do
    resource MyApp.Accounts.User do
      define :create_user, action: :create
      define :get_user, action: :by_id, get_by: [:id]
      define :list_users, action: :read
      define_calculation :account_risk_score, calculation: :risk_score
    end
  end

  jido do
    expose :create_user
    expose :get_user
    expose :list_users
    expose :account_risk_score
  end
end
```

An `expose` entity resolves one Ash code interface. It inherits:

- Resource and action.
- Public name and description.
- Positional arguments.
- Custom inputs.
- `get?` and `get_by` rules.
- Default options that are safe for generated use.
- Calculation definitions.

### 7.2 Direct action fallback

Allow a direct action declaration when no code interface exists.

```elixir
jido do
  action :rebuild_search_index, MyApp.Search.Index, :rebuild
end
```

Direct action declarations must be explicit. There is no automatic `all_actions` behavior in the new API.

### 7.3 Resource shorthand

Keep a resource form as shorthand for migration and local configuration.

```elixir
defmodule MyApp.Accounts.User do
  use Ash.Resource,
    domain: MyApp.Accounts,
    extensions: [AshJido]

  jido do
    action :create
    publish :create, type: "accounts.user.created", include: [:id, :email]
  end
end
```

The compiler normalizes resource declarations into the domain catalog. A descriptor can have only one source declaration. Duplicate declarations are compile errors.

### 7.4 Planned DSL entities

Core entities:

- `expose`
- `action`
- `publish`
- `persistence_store`

Later entities, after core contracts are stable:

- `bulk_action`
- Reactor exposure
- State-machine transition exposure

## 8. Action descriptor

The first version should contain at least these fields:

```elixir
defstruct [
  :id,
  :name,
  :module,
  :domain,
  :resource,
  :ash_action,
  :action_type,
  :source,
  :input_schema,
  :output_schema,
  :result_cardinality,
  :identity,
  :select,
  :load,
  :fingerprint
]
```

The generated module exposes `__ash_jido__/0`, which returns its descriptor.

`AshJido.Info` exposes functions for descriptors and generated modules. It returns errors when configuration is invalid. It must not silently hide failed generation.

### 8.1 Deterministic module ownership

The current generator skips compilation when `Code.ensure_loaded/1` finds a module. This can retain stale generated code.

The new compiler must:

- Compute a stable fingerprint from the normalized descriptor.
- Mark generated modules as owned by AshJido.
- Replace an old AshJido-generated module when its fingerprint changes.
- Reject a collision with a user module or a module generated by another owner.
- Produce a compile error that identifies both declarations in a duplicate collision.

## 9. Generated Action contract

### 9.1 Inputs

The input schema contains:

- Public Ash action arguments.
- Accepted public attributes.
- Required values based on the action, not only the resource attribute.
- Identity fields for get, update, and destroy operations.
- Explicit query controls for read actions.
- Explicitly allowed private inputs, when configured by name.

Replace `include_private?: true` with an explicit allowlist such as `private_inputs: [...]`.

Reject unknown or unsupported input types unless the declaration supplies an explicit Zoi schema override.

### 9.2 Results

Use one envelope for all generated Actions:

```elixir
%{
  result: serialized_result,
  page: optional_page_metadata,
  metadata: optional_action_metadata
}
```

For destroy actions:

```elixir
%{
  result: %{
    destroyed?: true,
    identity: %{id: id}
  },
  page: nil,
  metadata: nil
}
```

The serializer must not expose:

- `%Ash.NotLoaded{}`
- `%Ash.ForbiddenField{}`
- Changesets
- Queries
- Ash internal metadata
- Sensitive fields without an explicit allowlist

### 9.3 Execution context

Put all Ash execution options under one key:

```elixir
%{
  ash: %{
    actor: actor,
    tenant: tenant,
    scope: scope,
    authorize?: true,
    tracer: tracer,
    timeout: timeout,
    context: %{}
  }
}
```

Only trusted application code can set options that weaken authorization. Raw Action parameters can never disable authorization.

Remove arbitrary run-time domain selection.

### 9.4 Errors

Public errors use a stable set of categories:

- `invalid_input`
- `not_found`
- `forbidden`
- `conflict`
- `timeout`
- `internal`

Validation errors can include safe field messages. Internal errors do not include the original Ash exception, changeset, actor, query, or data-layer details.

Full errors can go to logs or telemetry only when the values are redacted.

## 10. Ash feature support

### 10.1 Code interfaces

Use public Ash code-interface metadata as the preferred source for generated Actions.

Support:

- Domain and resource code interfaces.
- Interface arguments.
- Custom inputs.
- Default options after a safety review.
- `get?`.
- `get_by`.
- Calculation interfaces.
- Interface descriptions.

### 10.2 Identities and result cardinality

Support:

- Primary keys.
- Named identities.
- Composite identities.
- Composite primary keys.
- `get?` read actions.
- `not_found_error?` behavior.
- Update and destroy actions that use identity fields instead of a record argument.

### 10.3 Calculations and aggregates

Generate read-only Jido Actions from exposed Ash calculation interfaces.

Support calculation arguments and typed results. Allow selected calculations and aggregates in result loads.

Do not create unrestricted aggregate or calculation execution endpoints.

### 10.4 Types and constraints

Map these Ash types and rules into Zoi schemas:

- Built-in scalar types.
- `Ash.Type.NewType`.
- Custom Ash types through an explicit mapper callback.
- Unions.
- Embedded resources.
- Arrays and item constraints.
- Maps with known field schemas.
- Decimal values.
- Enum values.
- Date and time values.
- String length and pattern constraints.
- Numeric minimum and maximum constraints.
- Action return types and constraints.

Use Ash `sensitive?` metadata for redaction in errors, signals, logs, and telemetry.

### 10.5 Select, load, calculations, and aggregates

Support static `select` and `load` rules on every action that returns records.

Allow dynamic selection or loading only through compile-time allowlists. Validate requested fields before execution.

The output schema must include the selected and loaded shape.

### 10.6 Pagination

Support native Ash pagination rules:

- Keyset pagination.
- Offset pagination.
- Required pagination.
- Optional counts.
- Compile-time maximum page sizes.
- Opaque before and after cursors.

Do not return Ash page structs. Normalize them into the Action result envelope.

### 10.7 Query controls

Replace the broad `query_params?: true` option with explicit controls:

```elixir
expose :list_users,
  filters: [:status, :created_at],
  sorts: [:created_at, :email],
  loads: [:profile],
  pagination: [type: :keyset, max_page_size: 50]
```

Use Ash input parsing for allowed filters and sorts. Never accept raw Ash expressions from external Action input.

### 10.8 Managed relationships

Support statically declared nested input for actions that use `manage_relationship`.

The generated schema can represent create, relate, update, unrelate, and destroy operations only when the Ash action explicitly accepts that shape.

Do not provide general relationship mutation input.

### 10.9 Authorization, field policies, and tenancy

- Pass actor, tenant, scope, and tracer to every Ash operation.
- Respect field policies during result serialization.
- Detect resources that require a tenant and give a clear error when none is present.
- Support `Ash.ToTenant` values.
- Do not perform an unauthorized read before update or destroy.
- Treat authorization discovery as an aid, not as the security boundary.

### 10.10 Policy-aware discovery

After the core compiler is stable, consider:

```elixir
AshJido.Info.available_actions(MyApp.Accounts,
  actor: actor,
  tenant: tenant,
  subject: user
)
```

This API can help an agent select valid tools. Every Action still performs authorization during execution.

### 10.11 Bulk actions

Add bulk support only through an explicit `bulk_action` declaration.

Support:

- Bulk create.
- Atomic bulk update when the data layer supports it.
- Atomic bulk destroy when the data layer supports it.
- Per-item errors.
- Batch limits.
- Controlled concurrency.

Bulk Actions need separate input, output, error, and transaction tests.

### 10.12 Features inherited from Ash

These features must work through normal Ash execution and do not need duplicate AshJido DSL options:

- Changes.
- Validations.
- Preparations.
- Policies.
- Manual actions.
- Action hooks.
- Transactions inside one Ash action.
- Resource notifiers.

Add integration tests to prove this behavior.

## 11. Jido Flow integration

Generated Actions already compose as normal Flow steps:

```elixir
step "create",
  action: MyApp.Accounts.Jido.CreateUser,
  params: %{email: input(:email)}
```

Do not add `AshJido.Flow` in the first release.

Document these rules:

- Each Flow step has its normal Ash transaction boundary.
- Independent Flow nodes can run in parallel.
- A later step failure cannot roll back prior external input or output.
- Multi-write atomic work belongs in one Ash generic action or one custom Jido Action that uses `Ash.transact/2`.
- Compensation is an explicit application Action or Flow branch.
- A Flow used as an Agent route must return a complete candidate Agent state. A CRUD result is not a complete Agent state.

Consider an `ash_step` syntax only after normal Flow use shows repeated code that the helper can safely remove.

## 12. Persistence adapter

### 12.1 Contract

`AshJido.Persistence.Adapter` implements `Jido.Persistence.Adapter`.

It stores binary keys and binary values. It does not inspect, decode, migrate, or project Jido checkpoint data.

### 12.2 User-owned resource

The application owns its resource, table, repository, domain, tenant, and migration.

```elixir
defmodule MyApp.System.JidoStore do
  use Ash.Resource,
    domain: MyApp.System,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJido]

  postgres do
    repo MyApp.Repo
    table "jido_persistence_records"
  end

  jido do
    persistence_store
  end
end
```

The extension validates or generates private storage fields for:

- `key`
- `value`
- `write_token`

The package must not ship a resource tied to an application repository or table.

### 12.3 Adapter configuration

```elixir
use Jido,
  persistence:
    {AshJido.Persistence.Adapter,
     resource: MyApp.System.JidoStore,
     domain: MyApp.System,
     tenant: "system",
     authorize?: false}
```

Persistence storage is internal infrastructure. It uses fixed private operations and does not accept an actor-controlled authorization option.

### 12.4 Atomic compare-and-swap

Jido requires one atomic compare-and-swap operation. A separate read and update is invalid.

The implementation must provide:

- One insert-if-absent statement for `:not_found`.
- One conditional update for an expected token or byte value.
- A new write token after every successful update, including a same-value update.
- `:conflict` when zero rows change because the expected value does not match.
- `{:rejected, reason}` only for a known failure before a write starts.
- `:indeterminate` when the write result is unknown.

### 12.5 Data-layer plan

Start with AshPostgres.

Use two layers:

1. `AshJido.Persistence.Adapter` implements the Jido behavior and validates options.
2. `AshJido.Persistence.Postgres` performs the exact atomic storage operation.

First, test whether a public Ash atomic bulk API can give all required guarantees. It must force atomic execution and return an exact result count. If it cannot, use a small AshPostgres-specific repository operation behind the driver.

Do not claim generic Ash data-layer support until a driver passes the persistence conformance suite.

Do not use Ash ETS for persistence CAS. Use Jido's ETS persistence adapter for development and tests that do not need Ash storage.

### 12.6 Persistence rules

- Use one fixed tenant or database prefix for one adapter instance.
- Do not parse the opaque Jido storage key to select a tenant.
- Do not add automatic retention.
- Preserve tombstones that Jido needs to reject stale writers.
- Make physical deletion an explicit maintenance operation.
- Keep queryable projections in a separate resource.
- Let Jido own checkpoint format migrations.
- Let the application own database migrations.

## 13. Signals and telemetry

### 13.1 Signals

Keep Ash notifier integration for resource lifecycle events.

The first release should not emit a second signal directly from each generated Action. This prevents duplicate events with different failure behavior.

Publication rules must use:

- Explicit signal types.
- Public or selected fields.
- Correlation and causation identifiers when available.
- Redaction for sensitive values.
- Best-effort delivery with clear failure telemetry.

A dispatch failure cannot undo an Ash action that already committed.

If an application needs reliable delivery, add a separate optional outbox design with a user-owned resource. Do not hide an outbox inside the notifier.

### 13.2 Telemetry

Use Jido Action, Jido Flow, Jido persistence, Ash, and Jido Signal telemetry for their own lifecycle events.

Keep only AshJido-specific events that add bridge information, such as:

- Descriptor compilation.
- Schema conversion failures.
- Serialization and redaction failures.
- Persistence driver results.
- Signal publication mapping failures.

Do not duplicate Jido Action start and stop events.

## 14. AshAi and Jido AI boundary

Use AshAi when an application wants direct LLM access to Ash actions, ReqLLM tools, MCP, or vectorization.

Use AshJido with Jido AI when an Ash action must participate in Jido Agents or Jido Flows.

Rules:

- Do not depend on AshAi.
- Do not call `AshAi.OpenApi`, `AshAi.Serializer`, or internal tool builders.
- Reuse public DSL terms where they have the same meaning: `load`, `identity`, `action_parameters`, and explicit names.
- Add a compatibility fixture that compares equivalent AshAi and AshJido action schemas and execution behavior.
- Use `Jido.AI.ToolAdapter` to convert generated Jido Actions into model tools.
- Do not make a shared Ash/AshAi descriptor part of the first release.

A neutral public Ash action descriptor can be a later joint design with Ash and AshAi maintainers.

## 15. Dependencies

Expected run-time dependencies:

- `ash`
- `jido`
- `jido_action`
- `jido_signal`
- `zoi`

Do not add these dependencies unless a later feature directly requires one:

- `ash_ai`
- `jido_ai`
- `req_llm`
- `ash_postgres` as a required package dependency

AshPostgres persistence support can compile conditionally or use a behavior boundary, but the public package must give a clear error when the driver is not available.

Review whether `splode` remains necessary after the new safe error layer is complete.

The beta implementation uses published Hex packages for Jido, Jido Action,
Jido Signal, and Zoi. Do not add local path or Git overrides to the release
branch.

## 16. Migration from the current package

| Current feature | Jido v3 plan |
| --- | --- |
| Resource `action` DSL | Keep as shorthand and direct-action fallback |
| Run-time domain in context | Remove; bind the domain at compile time |
| `all_actions` | Deprecate and remove from the new API |
| `output_map?` | Remove; always use the stable result envelope |
| `include_private?` | Replace with explicit private input and output allowlists |
| `query_params?` | Replace with explicit filter, sort, load, and pagination rules |
| Read-only `load` support | Extend to all record-returning actions |
| Primary-key-only update and destroy | Add named and composite identities |
| `AshJido.Tools` | Remove; use `AshJido.Info.action_modules/1` |
| Sensor dispatch bridge | Remove; Jido owns sensors and the signal bus |
| Direct generated-Action signals | Remove from the first release |
| Raw Ash errors in Jido error details | Remove and redact |
| `Code.ensure_loaded/1` generation skip | Replace with ownership fingerprints |
| `category`, `tags`, and `vsn` DSL fields | Remove unless a Jido v3 consumer has a direct need |

Provide a migration guide with old and new DSL examples before the first release candidate.

## 17. Delivery plan

### Phase 0: Baseline and decisions

- Create `release/v3` from current `main`.
- Add this plan.
- Record the package version decision.
- Select temporary Jido v3 dependency sources.
- Add a minimal consumer fixture that uses local Jido v3.
- Record existing tests that must remain as migration coverage.

Exit condition: the branch has a known dependency baseline and a small application can compile against Jido v3.

### Phase 1: Descriptor and compiler

- Add `AshJido.ActionDescriptor`.
- Add domain DSL support.
- Add code-interface resolution.
- Keep direct resource actions as shorthand.
- Add descriptor normalization and fingerprints.
- Add deterministic module ownership and collision errors.
- Add `AshJido.Info` descriptor and module APIs.

Exit condition: compile-time tests cover code interfaces, direct actions, duplicates, stale fingerprints, and invalid configuration.

### Phase 2: Action contracts and runtime

- Replace NimbleOptions-style generation with Jido v3 Zoi schemas.
- Add full input and output schemas.
- Add identities and result cardinality.
- Add the stable result envelope.
- Add safe serialization and errors.
- Add namespaced Ash context.
- Remove unauthorized pre-read behavior.
- Add richer Ash type and constraint support.

Exit condition: create, read, update, destroy, generic actions, and calculations pass contract tests with policies and tenants enabled.

### Phase 3: Flow composition

- Add direct Flow examples.
- Test sequential and parallel steps.
- Test partial failure behavior.
- Test a route Flow that returns a complete Agent state.
- Document transaction and compensation limits.

Exit condition: no AshJido-specific Flow runtime is necessary for normal use.

### Phase 4: AshPostgres persistence

- Build a persistence resource extension.
- Complete the atomic-operation spike.
- Add the Postgres driver.
- Implement the Jido persistence behavior.
- Add migration templates or an Igniter installer.
- Add the persistence conformance suite.
- Test agent activation, checkpoint, hibernation, thaw, and conflict recovery.

Exit condition: concurrent writers cannot lose an update, and all unknown write outcomes are reported as indeterminate.

### Phase 5: Signals and telemetry

- Keep one notifier publication path.
- Remove duplicate generated-Action signal emission.
- Add safe publication selection and redaction.
- Add correlation and causation metadata.
- Remove duplicate telemetry spans.
- Keep bridge-specific telemetry.

Exit condition: one Ash change produces no duplicate event and no private data leak.

### Phase 6: AshAi alignment and release work

- Add AshAi compatibility fixtures without a run-time dependency.
- Test Jido AI tool conversion.
- Add migration and upgrade guides.
- Add a full consumer matrix.
- Update dependency requirements from development sources to released versions.
- Run package quality, documentation, and release checks.

Exit condition: a consumer can use AshJido Actions in Jido Exec, Flow, Agent routes, persistence, Signals, and Jido AI.

## 18. Test strategy

### 18.1 Compiler tests

- Domain and resource DSL normalization.
- Code-interface resolution.
- Duplicate names and module collisions.
- Fingerprint changes.
- Unsupported type failures.
- Private input and output validation.

### 18.2 Action contract tests

- All Ash action types.
- Named and composite identities.
- `get?` and list cardinality.
- Custom action return types.
- Calculations and aggregates.
- Select and load behavior.
- Keyset and offset pagination.
- Managed relationships.
- Sensitive value redaction.

### 18.3 Security tests

- Actor and tenant propagation.
- Field policies.
- Forbidden reads, updates, and destroys.
- Missing tenant failures.
- Attempts to disable authorization through parameters.
- Error and telemetry redaction.

### 18.4 Flow tests

- Sequential data references.
- Parallel branches.
- Step failure.
- Complete Agent-state return.
- No claim of rollback across completed steps.

### 18.5 Persistence tests

- Missing-key insert.
- Expected-value update.
- Token update.
- Same-value update.
- Conflict classification.
- Concurrent writers.
- Delete and tombstone behavior.
- Timeout and connection failures.
- Unknown write outcomes.
- Fixed tenant or prefix behavior.
- Jido lifecycle recovery.

### 18.6 Consumer tests

Run at least these consumers in CI:

- Base Ash plus generated Jido Action.
- Jido Flow composition.
- Jido Agent route.
- AshPostgres persistence.
- Jido Signal publication.
- Jido AI tool conversion.
- AshAi compatibility fixture.

## 19. Branch strategy

- `main` remains the maintenance branch for the current AshJido release line.
- `release/v3` is the integration branch for Jido v3 work.
- Feature branches start from `release/v3` and merge back into `release/v3`.
- Use names such as `feat/v3-action-compiler` and `feat/v3-ash-persistence`.
- Apply urgent compatible fixes to `main`, then forward-port them to `release/v3` when needed.
- Do not merge the breaking branch into `main` until the release candidate is complete.

## 20. Resolved implementation decisions

1. The package release is AshJido `3.0.0-beta.1`.
2. Ash code interfaces are the preferred action source. Direct actions remain a fallback.
3. All Jido dependencies use published Hex releases.
4. Persistence uses the `Jido.Persistence.Adapter` byte contract and requires an Ash data layer with atomic query updates. Production data-layer conformance remains a release-candidate gate.
5. `jido_signal` is a required dependency for explicit notifier publications.
6. Resource-level shorthand remains supported during the version 3 beta line.
7. AshJido does not require a Jido Plugin and does not add an AshJido topology runtime. Generated Actions, the persistence adapter, and notifier Signals use native Jido extension points.

## 21. First implementation slice

The first feature branch should be `feat/v3-action-compiler`.

It should contain only:

- Jido v3 dependency updates.
- `AshJido.ActionDescriptor`.
- Domain DSL with one `expose` entity.
- Resolution of one Ash code interface.
- One generated Jido v3 Action.
- Fingerprinted module ownership.
- `AshJido.Info.descriptors/1` and `AshJido.Info.action_modules/1`.
- Compile-time and end-to-end tests for one create action and one `get?` read action.

Do not add persistence, signals, bulk actions, or Flow syntax in this first slice.

## 22. Definition of done

The Jido v3 work is complete when:

- The public DSL is smaller than the current DSL.
- Generated modules are deterministic and cannot remain stale after configuration changes.
- Input, output, and error contracts are static, safe, and documented.
- Policies, field policies, actors, tenants, and sensitive fields work correctly.
- Standard Jido Flow uses generated Actions directly.
- AshPostgres persistence passes the Jido persistence conformance suite under concurrency.
- Signal publication does not duplicate events or expose private values.
- Jido AI can use generated Actions without an AshJido tool layer.
- AshAi and AshJido have clear, tested, non-overlapping roles.
- The package passes `mix quality` and all consumer integration tests.
