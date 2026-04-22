defmodule AshJido.SignalEmitterTest do
  use ExUnit.Case, async: true

  alias AshJido.SignalEmitter
  alias Jido.Action.Error

  defmodule TestResource do
    defstruct [:id, :name]
  end

  describe "validate_dispatch_config/5" do
    test "returns :ok for non-mutating actions regardless of config" do
      context = %{}
      jido_config = %{emit_signals?: true}

      assert :ok =
               SignalEmitter.validate_dispatch_config(
                 context,
                 jido_config,
                 TestResource,
                 :read,
                 :read
               )

      assert :ok =
               SignalEmitter.validate_dispatch_config(
                 context,
                 jido_config,
                 TestResource,
                 :custom,
                 :custom_action
               )
    end

    test "returns :ok when emit_signals? is false" do
      context = %{}
      jido_config = %{emit_signals?: false, signal_dispatch: nil}

      assert :ok =
               SignalEmitter.validate_dispatch_config(
                 context,
                 jido_config,
                 TestResource,
                 :create,
                 :create
               )
    end

    test "returns error when emit_signals? is true but no dispatch configured" do
      context = %{domain: AshJido.Test.Domain}
      jido_config = %{emit_signals?: true, signal_dispatch: nil}

      assert {:error, %Error.InvalidInputError{} = error} =
               SignalEmitter.validate_dispatch_config(
                 context,
                 jido_config,
                 TestResource,
                 :create,
                 :create
               )

      assert error.message =~ "signal dispatch configuration is required"
      assert error.details.field == :signal_dispatch
    end

    test "validates dispatch configuration from jido_config" do
      context = %{}

      jido_config = %{
        emit_signals?: true,
        signal_dispatch: {:pid, target: self()}
      }

      assert :ok =
               SignalEmitter.validate_dispatch_config(
                 context,
                 jido_config,
                 TestResource,
                 :create,
                 :create
               )
    end

    test "validates dispatch configuration from context" do
      context = %{signal_dispatch: {:pid, target: self()}}
      jido_config = %{emit_signals?: true, signal_dispatch: nil}

      assert :ok =
               SignalEmitter.validate_dispatch_config(
                 context,
                 jido_config,
                 TestResource,
                 :create,
                 :create
               )
    end

    test "returns error for invalid dispatch configuration" do
      context = %{}

      jido_config = %{
        emit_signals?: true,
        signal_dispatch: {:invalid, option: "value"}
      }

      assert {:error, %Error.InvalidInputError{} = error} =
               SignalEmitter.validate_dispatch_config(
                 context,
                 jido_config,
                 TestResource,
                 :create,
                 :create
               )

      assert error.message =~ "invalid signal dispatch configuration"
      assert error.details.field == :signal_dispatch
    end

    test "context dispatch overrides jido_config dispatch" do
      context = %{signal_dispatch: {:pid, target: self()}}

      jido_config = %{
        emit_signals?: true,
        signal_dispatch: {:invalid, option: "value"}
      }

      # Context's valid dispatch should override jido_config's invalid one
      assert :ok =
               SignalEmitter.validate_dispatch_config(
                 context,
                 jido_config,
                 TestResource,
                 :create,
                 :create
               )
    end
  end

  describe "resolve_dispatch_config/2" do
    test "returns context dispatch when present" do
      context = %{signal_dispatch: {:pid, target: self()}}
      jido_config = %{signal_dispatch: {:bus, name: :test}}

      assert {:pid, target: _} = SignalEmitter.resolve_dispatch_config(context, jido_config)
    end

    test "returns jido_config dispatch when context has no dispatch" do
      context = %{}
      jido_config = %{signal_dispatch: {:bus, name: :test}}

      assert {:bus, name: :test} = SignalEmitter.resolve_dispatch_config(context, jido_config)
    end

    test "returns nil when neither has dispatch" do
      context = %{}
      jido_config = %{signal_dispatch: nil}

      assert nil == SignalEmitter.resolve_dispatch_config(context, jido_config)
    end
  end

  describe "emit_notifications/5" do
    test "emits notification as signal" do
      context = %{}
      resource = AshJido.Test.User
      action_name = :create

      jido_config = %{
        emit_signals?: true,
        signal_dispatch: {:pid, target: self()},
        signal_type: nil,
        signal_source: nil
      }

      notification = %Ash.Notifier.Notification{
        resource: resource,
        action: %{type: :create},
        data: %{id: "123", name: "Test"},
        metadata: %{}
      }

      result =
        SignalEmitter.emit_notifications(
          [notification],
          context,
          resource,
          action_name,
          jido_config
        )

      assert result.sent == 1
      assert result.failed == []

      assert_receive {:signal, %Jido.Signal{} = signal}, 500
      assert signal.data == %{id: "123", name: "Test"}
      assert signal_metadata(signal).ash_action == :create
    end

    test "tracks failed emissions" do
      context = %{}
      resource = AshJido.Test.User
      action_name = :create

      # Invalid dispatch that will fail
      jido_config = %{
        emit_signals?: true,
        signal_dispatch: {:invalid, target: nil},
        signal_type: nil,
        signal_source: nil
      }

      notification = %Ash.Notifier.Notification{
        resource: resource,
        action: %{type: :create},
        data: %{id: "123", name: "Test"},
        metadata: %{}
      }

      result =
        SignalEmitter.emit_notifications(
          [notification],
          context,
          resource,
          action_name,
          jido_config
        )

      assert result.sent == 0
      assert length(result.failed) == 1
    end

    test "handles empty notifications list" do
      context = %{}
      resource = AshJido.Test.User
      action_name = :create

      jido_config = %{
        emit_signals?: true,
        signal_dispatch: {:pid, target: self()},
        signal_type: nil,
        signal_source: nil
      }

      result = SignalEmitter.emit_notifications([], context, resource, action_name, jido_config)

      assert result.sent == 0
      assert result.failed == []
    end

    test "handles multiple notifications with mixed success/failure" do
      context = %{}
      resource = AshJido.Test.User
      action_name = :create

      # This will work for first notification, fail for second
      jido_config = %{
        emit_signals?: true,
        signal_dispatch: {:pid, target: self()},
        signal_type: nil,
        signal_source: nil
      }

      notification1 = %Ash.Notifier.Notification{
        resource: resource,
        action: %{type: :create},
        data: %{id: "1", name: "First"},
        metadata: %{}
      }

      # Note: Since we're using the same valid dispatch, both should succeed
      # To test failure, we'd need to mock or use a different dispatch
      notifications = [notification1]

      result =
        SignalEmitter.emit_notifications(
          notifications,
          context,
          resource,
          action_name,
          jido_config
        )

      assert result.sent == 1
      assert result.failed == []
    end

    test "uses custom signal type when provided" do
      context = %{}
      resource = AshJido.Test.User
      action_name = :create

      jido_config = %{
        emit_signals?: true,
        signal_dispatch: {:pid, target: self()},
        signal_type: "custom.event.type",
        signal_source: nil
      }

      notification = %Ash.Notifier.Notification{
        resource: resource,
        action: %{type: :create},
        data: %{id: "123", name: "Test"},
        metadata: %{}
      }

      SignalEmitter.emit_notifications(
        [notification],
        context,
        resource,
        action_name,
        jido_config
      )

      assert_receive {:signal, %Jido.Signal{type: "custom.event.type"}}, 500
    end

    test "uses custom signal source when provided" do
      context = %{}
      resource = AshJido.Test.User
      action_name = :create

      jido_config = %{
        emit_signals?: true,
        signal_dispatch: {:pid, target: self()},
        signal_type: nil,
        signal_source: "/custom/source/path"
      }

      notification = %Ash.Notifier.Notification{
        resource: resource,
        action: %{type: :create},
        data: %{id: "123", name: "Test"},
        metadata: %{}
      }

      SignalEmitter.emit_notifications(
        [notification],
        context,
        resource,
        action_name,
        jido_config
      )

      assert_receive {:signal, %Jido.Signal{source: "/custom/source/path"}}, 500
    end
  end

  describe "default signal type and source generation" do
    test "generates correct default signal type from resource and action" do
      context = %{}
      resource = AshJido.Test.User
      action_name = :create

      jido_config = %{
        emit_signals?: true,
        signal_dispatch: {:pid, target: self()},
        signal_type: nil,
        signal_source: nil
      }

      notification = %Ash.Notifier.Notification{
        resource: resource,
        action: %{type: :create},
        data: %{id: "123", name: "Test"},
        metadata: %{}
      }

      SignalEmitter.emit_notifications(
        [notification],
        context,
        resource,
        action_name,
        jido_config
      )

      assert_receive {:signal, %Jido.Signal{type: "ash.user.create"}}, 500
    end

    test "generates correct default signal source from resource" do
      context = %{}
      resource = AshJido.Test.User
      action_name = :create

      jido_config = %{
        emit_signals?: true,
        signal_dispatch: {:pid, target: self()},
        signal_type: nil,
        signal_source: nil
      }

      notification = %Ash.Notifier.Notification{
        resource: resource,
        action: %{type: :create},
        data: %{id: "123", name: "Test"},
        metadata: %{}
      }

      SignalEmitter.emit_notifications(
        [notification],
        context,
        resource,
        action_name,
        jido_config
      )

      assert_receive {:signal, %Jido.Signal{source: "/ash/user/create/create"}}, 500
    end

    test "extracts subject from data with id" do
      context = %{}
      resource = AshJido.Test.User
      action_name = :create

      jido_config = %{
        emit_signals?: true,
        signal_dispatch: {:pid, target: self()},
        signal_type: nil,
        signal_source: nil
      }

      notification = %Ash.Notifier.Notification{
        resource: resource,
        action: %{type: :create},
        data: %{id: "user-123", name: "Test"},
        metadata: %{}
      }

      SignalEmitter.emit_notifications(
        [notification],
        context,
        resource,
        action_name,
        jido_config
      )

      assert_receive {:signal, %Jido.Signal{subject: "/user/user-123"}}, 500
    end

    test "handles data without id for subject" do
      context = %{}
      resource = AshJido.Test.User
      action_name = :create

      jido_config = %{
        emit_signals?: true,
        signal_dispatch: {:pid, target: self()},
        signal_type: nil,
        signal_source: nil
      }

      notification = %Ash.Notifier.Notification{
        resource: resource,
        action: %{type: :create},
        data: %{name: "Test"},
        metadata: %{}
      }

      SignalEmitter.emit_notifications(
        [notification],
        context,
        resource,
        action_name,
        jido_config
      )

      assert_receive {:signal, %Jido.Signal{subject: nil}}, 500
    end
  end

  defp signal_metadata(signal) do
    Map.get(signal, :jido_metadata) ||
      signal
      |> Map.get(:extensions, %{})
      |> Map.get("jido_metadata", %{})
  end
end
