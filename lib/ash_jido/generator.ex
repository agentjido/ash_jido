defmodule AshJido.Generator do
  @moduledoc false

  alias AshJido.TypeMapper
  alias Spark.Dsl.Transformer

  @doc """
  Generates a Jido.Action module for the given Ash action.

  Returns the module name that was generated.
  """
  def generate_jido_action_module(resource, jido_action, dsl_state) do
    ash_action = get_ash_action(resource, jido_action.action, dsl_state)
    validate_jido_action_options!(resource, ash_action, jido_action)
    module_name = build_module_name(resource, jido_action, ash_action)
    module_ast = build_module_ast(resource, ash_action, jido_action, module_name, dsl_state)

    case Code.ensure_loaded(module_name) do
      {:module, _} ->
        :ok

      {:error, _} ->
        Code.compile_quoted(module_ast)
    end

    module_name
  end

  defp get_ash_action(resource, action_name, dsl_state) do
    # Get all actions from the actions section using Spark transformer
    all_actions = Transformer.get_entities(dsl_state, [:actions])

    Enum.find(all_actions, fn action ->
      action.name == action_name
    end) ||
      raise "Action #{action_name} not found in resource #{inspect(resource)}. Available: #{inspect(Enum.map(all_actions, &{&1.name, &1.type}))}"
  end

  defp build_module_name(resource, jido_action, ash_action) do
    case jido_action.module_name do
      nil ->
        # Use default module naming
        _resource_name = resource |> Module.split() |> List.last()
        action_name = ash_action.name |> to_string() |> Macro.camelize()

        base_module = Module.concat([resource, "Jido"])
        Module.concat([base_module, action_name])

      custom_module_name ->
        # Use the custom module name provided in DSL
        custom_module_name
    end
  end

  defp build_module_ast(resource, ash_action, jido_action, module_name, dsl_state) do
    action_name = jido_action.name || build_default_action_name(resource, ash_action)

    description =
      jido_action.description || ash_action.description || "Ash action: #{ash_action.name}"

    # Build input schema including accepted attributes
    schema = build_parameter_schema(resource, ash_action, dsl_state)

    quote do
      defmodule unquote(module_name) do
        @moduledoc """
        Generated Jido action for `#{unquote(resource)}.#{unquote(ash_action.name)}`.

        Wraps the Ash action; see the resource docs for semantics.
        """

        use Jido.Action,
          name: unquote(action_name),
          description: unquote(description),
          schema: unquote(Macro.escape(schema))

        @resource unquote(resource)
        @ash_action unquote(ash_action.name)
        @ash_action_type unquote(ash_action.type)
        @jido_config unquote(Macro.escape(jido_action))

        def run(params, context) do
          ash_opts = AshJido.Context.extract_ash_opts!(context, @resource, @ash_action)
          telemetry_meta = telemetry_metadata(ash_opts, @jido_config)
          telemetry_span = AshJido.Telemetry.start(@jido_config, telemetry_meta)

          {result, signal_meta, exception?} =
            case AshJido.SignalEmitter.validate_dispatch_config(
                   context,
                   @jido_config,
                   @resource,
                   @ash_action,
                   @ash_action_type
                 ) do
              :ok ->
                execute_action(params, context, ash_opts, telemetry_span)

              {:error, error} ->
                {{:error, error}, empty_signal_meta(), false}
            end

          if exception? do
            result
          else
            AshJido.Telemetry.stop(telemetry_span, result, signal_meta)
            result
          end
        end

        defp execute_action(params, context, ash_opts, telemetry_span) do
          try do
            case @ash_action_type do
              :create ->
                create_result =
                  @resource
                  |> Ash.Changeset.for_create(@ash_action, params, ash_opts)
                  |> Ash.create!(
                    maybe_add_notification_collection(ash_opts, @jido_config, :create)
                  )

                {result, notifications} = maybe_extract_result_and_notifications(create_result)

                signal_emission =
                  maybe_emit_notifications(
                    notifications,
                    context,
                    @jido_config,
                    @resource,
                    @ash_action,
                    :create
                  )

                action_result = {:ok, result} |> AshJido.Mapper.wrap_result(@jido_config)
                {action_result, signal_emission, false}

              :read ->
                result =
                  @resource
                  |> Ash.Query.for_read(@ash_action, params, ash_opts)
                  |> maybe_load(@jido_config)
                  |> Ash.read!(ash_opts)

                # Ash.read! returns a raw list, not {:ok, result}
                # Pass it directly to Mapper.wrap_result which will wrap it
                action_result = AshJido.Mapper.wrap_result(result, @jido_config)
                {action_result, empty_signal_meta(), false}

              :update ->
                # Load the record to update using its primary key
                record_id = Map.get(params, :id) || Map.get(params, "id")

                unless record_id do
                  raise ArgumentError, "Update actions require an 'id' parameter"
                end

                # Remove id from params to prevent it being passed to changeset
                update_params = Map.drop(params, [:id, "id"])

                # Load the record first
                record =
                  @resource
                  |> Ash.get!(record_id, ash_opts)

                update_result =
                  record
                  |> Ash.Changeset.for_update(@ash_action, update_params, ash_opts)
                  |> Ash.update!(
                    maybe_add_notification_collection(ash_opts, @jido_config, :update)
                  )

                {result, notifications} = maybe_extract_result_and_notifications(update_result)

                signal_emission =
                  maybe_emit_notifications(
                    notifications,
                    context,
                    @jido_config,
                    @resource,
                    @ash_action,
                    :update
                  )

                action_result = {:ok, result} |> AshJido.Mapper.wrap_result(@jido_config)
                {action_result, signal_emission, false}

              :destroy ->
                # Load the record to destroy using its primary key
                record_id = Map.get(params, :id) || Map.get(params, "id")

                unless record_id do
                  raise ArgumentError, "Destroy actions require an 'id' parameter"
                end

                # Load the record first
                record =
                  @resource
                  |> Ash.get!(record_id, ash_opts)

                destroy_result =
                  record
                  |> Ash.Changeset.for_destroy(@ash_action, %{}, ash_opts)
                  |> Ash.destroy!(
                    maybe_add_notification_collection(ash_opts, @jido_config, :destroy)
                  )

                notifications = maybe_extract_destroy_notifications(destroy_result)

                signal_emission =
                  maybe_emit_notifications(
                    notifications,
                    context,
                    @jido_config,
                    @resource,
                    @ash_action,
                    :destroy
                  )

                # Pass :ok directly to Mapper which will convert to {:ok, nil}
                action_result = AshJido.Mapper.wrap_result(:ok, @jido_config)
                {action_result, signal_emission, false}

              :action ->
                result =
                  @resource
                  |> Ash.ActionInput.for_action(@ash_action, params, ash_opts)
                  |> Ash.run_action!(ash_opts)

                action_result = {:ok, result} |> AshJido.Mapper.wrap_result(@jido_config)
                {action_result, empty_signal_meta(), false}
            end
          rescue
            error ->
              stacktrace = __STACKTRACE__
              signal_meta = empty_signal_meta()

              AshJido.Telemetry.exception(telemetry_span, :error, error, stacktrace, signal_meta)

              jido_error = AshJido.Error.from_ash(error)
              {{:error, jido_error}, signal_meta, true}
          end
        end

        defp telemetry_metadata(ash_opts, config) do
          %{
            resource: @resource,
            ash_action_name: @ash_action,
            ash_action_type: @ash_action_type,
            generated_module: __MODULE__,
            domain: Keyword.get(ash_opts, :domain),
            tenant: Keyword.get(ash_opts, :tenant),
            actor_present?: not is_nil(Keyword.get(ash_opts, :actor)),
            signaling_enabled?: config.emit_signals?,
            read_load_configured?: not is_nil(config.load)
          }
        end

        defp empty_signal_meta, do: %{failed: [], sent: 0}

        defp maybe_load(query, config) do
          case config.load do
            nil -> query
            load -> Ash.Query.load(query, load)
          end
        end

        defp maybe_add_notification_collection(ash_opts, config, action_type) do
          if action_type in [:create, :update, :destroy] and config.emit_signals? do
            Keyword.put(ash_opts, :return_notifications?, true)
          else
            ash_opts
          end
        end

        defp maybe_extract_result_and_notifications({result, notifications})
             when is_list(notifications) do
          {result, notifications}
        end

        defp maybe_extract_result_and_notifications(result), do: {result, []}

        defp maybe_extract_destroy_notifications(notifications) when is_list(notifications),
          do: notifications

        defp maybe_extract_destroy_notifications({_result, notifications})
             when is_list(notifications),
             do: notifications

        defp maybe_extract_destroy_notifications(_), do: []

        defp maybe_emit_notifications(
               notifications,
               context,
               config,
               resource,
               action_name,
               action_type
             ) do
          if action_type in [:create, :update, :destroy] and config.emit_signals? do
            AshJido.SignalEmitter.emit_notifications(
              notifications,
              context,
              resource,
              action_name,
              config
            )
          else
            empty_signal_meta()
          end
        end
      end
    end
  end

  defp validate_jido_action_options!(resource, ash_action, jido_action) do
    if not is_nil(jido_action.load) and ash_action.type != :read do
      raise ArgumentError,
            "AshJido: :load option is only supported for read actions. #{inspect(resource)}.#{ash_action.name} is a #{ash_action.type} action."
    end
  end

  defp build_default_action_name(resource, ash_action) do
    resource_name =
      resource
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    # Create more intuitive action names based on type and context
    case ash_action.type do
      :create ->
        "create_#{resource_name}"

      :read ->
        # Use more descriptive names for read actions
        case ash_action.name do
          :get -> "get_#{resource_name}"
          :read -> "list_#{pluralize(resource_name)}"
          :by_id -> "get_#{resource_name}_by_id"
          name -> "#{resource_name}_#{name}"
        end

      :update ->
        "update_#{resource_name}"

      :destroy ->
        "delete_#{resource_name}"

      :action ->
        # For custom actions, use the action name as primary identifier
        case ash_action.name do
          name when name in [:activate, :deactivate, :archive, :restore] ->
            "#{name}_#{resource_name}"

          name ->
            "#{resource_name}_#{name}"
        end
    end
  end

  defp build_parameter_schema(resource, ash_action, dsl_state) do
    case ash_action.type do
      :create ->
        # Create actions use accepted attributes plus action arguments
        accepted_attrs = accepted_attributes_to_schema(resource, ash_action, dsl_state)
        action_args = action_args_to_schema(ash_action.arguments || [])
        accepted_attrs ++ action_args

      :update ->
        # Update actions need an id field plus accepted attributes plus action arguments
        base = [id: [type: :string, required: true, doc: "ID of record to update"]]
        accepted_attrs = accepted_attributes_to_schema(resource, ash_action, dsl_state)
        action_args = action_args_to_schema(ash_action.arguments || [])
        base ++ accepted_attrs ++ action_args

      :destroy ->
        # Destroy actions just need an id
        [id: [type: :string, required: true, doc: "ID of record to destroy"]]

      _ ->
        # Read and custom actions use their declared arguments
        action_args_to_schema(ash_action.arguments || [])
    end
  end

  defp accepted_attributes_to_schema(_resource, ash_action, dsl_state) do
    # Get the list of accepted attribute names from the action
    accepted_names = ash_action.accept || []

    # Get all attributes from the resource
    all_attributes = Transformer.get_entities(dsl_state, [:attributes])

    # Filter to only accepted attributes and convert to schema entries
    accepted_names
    |> Enum.map(fn attr_name ->
      attr = Enum.find(all_attributes, &(&1.name == attr_name))

      if attr do
        {attr_name, attribute_to_nimble_options(attr)}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp attribute_to_nimble_options(attr) do
    base_type = TypeMapper.map_ash_type(attr.type)

    opts = [type: base_type]

    # For create actions, attributes without allow_nil? false are required
    # unless they have a default value
    opts =
      if attr.allow_nil? == false and is_nil(attr.default) do
        Keyword.put(opts, :required, true)
      else
        opts
      end

    # Add description if available
    opts =
      case attr.description do
        desc when is_binary(desc) -> Keyword.put(opts, :doc, desc)
        _ -> opts
      end

    opts
  end

  defp action_args_to_schema(arguments) do
    Enum.map(arguments, fn arg ->
      {arg.name, TypeMapper.ash_type_to_nimble_options(arg.type, arg)}
    end)
  end

  defp pluralize(word) do
    cond do
      String.ends_with?(word, "y") ->
        String.slice(word, 0..-2//-1) <> "ies"

      String.ends_with?(word, ["s", "sh", "ch", "x", "z"]) ->
        word <> "es"

      true ->
        word <> "s"
    end
  end
end
