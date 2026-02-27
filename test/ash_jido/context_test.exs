defmodule AshJido.ContextTest do
  use ExUnit.Case, async: true

  alias AshJido.Context

  describe "extract_ash_opts!/3" do
    test "raises when domain is missing with helpful message" do
      assert_raise ArgumentError,
                   "AshJido: :domain must be provided in context for AshJido.Test.User.read",
                   fn ->
                     Context.extract_ash_opts!(%{}, AshJido.Test.User, :read)
                   end
    end

    test "includes existing base options and optional passthrough keys when provided" do
      tracer = [FakeTracer]
      scope = %{scope: :value}
      nested_context = %{request_id: "req_123"}

      opts =
        Context.extract_ash_opts!(
          %{
            domain: AshJido.Test.Domain,
            actor: %{id: "actor_1"},
            tenant: "org_1",
            authorize?: false,
            tracer: tracer,
            scope: scope,
            context: nested_context,
            timeout: 15_000
          },
          AshJido.Test.User,
          :register
        )

      assert opts[:domain] == AshJido.Test.Domain
      assert opts[:actor] == %{id: "actor_1"}
      assert opts[:tenant] == "org_1"
      assert opts[:authorize?] == false
      assert opts[:tracer] == tracer
      assert opts[:scope] == scope
      assert opts[:context] == nested_context
      assert opts[:timeout] == 15_000
    end

    test "does not include optional passthrough keys when absent" do
      opts =
        Context.extract_ash_opts!(
          %{domain: AshJido.Test.Domain},
          AshJido.Test.User,
          :read
        )

      assert opts[:domain] == AshJido.Test.Domain
      assert Keyword.has_key?(opts, :actor)
      assert Keyword.has_key?(opts, :tenant)
      refute Keyword.has_key?(opts, :authorize?)
      refute Keyword.has_key?(opts, :tracer)
      refute Keyword.has_key?(opts, :scope)
      refute Keyword.has_key?(opts, :context)
      refute Keyword.has_key?(opts, :timeout)
    end
  end
end
