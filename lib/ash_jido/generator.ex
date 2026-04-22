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

  @doc """
  Returns the fully qualified module name that would be generated for the
  given `jido_action` entry on `resource`. Performs no compilation.

  Used by the DSL transformer to validate that a resource's `jido` entries
  resolve to distinct module names before any of them are generated.
  """
  def target_module_name(resource, jido_action, dsl_state) do
    ash_action = get_ash_action(resource, jido_action.action, dsl_state)
    build_module_name(resource, jido_action, ash_action)
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
        action_name = ash_action.name |> to_string() |> Macro.camelize()

        Module.concat([resource, "Jido", action_name])

      custom_module_name ->
        # Use the custom module name provided in DSL
        custom_module_name
    end
  end

  defp build_module_ast(resource, ash_action, jido_action, module_name, dsl_state) do
    action_name = jido_action.name || build_default_action_name(resource, ash_action)

    description =
      jido_action.description || ash_action.description || "Ash action: #{ash_action.name}"

    tags = jido_action.tags || []
    category = jido_action.category
    vsn = jido_action.vsn

    # Build input schema including accepted attributes
    schema = build_parameter_schema(resource, ash_action, jido_action, dsl_state)
    primary_key = primary_key_fields(dsl_state)

    action_use_opts =
      [
        name: action_name,
        description: description,
        tags: tags,
        schema: schema
      ]
      |> maybe_put_option(:category, category)
      |> maybe_put_option(:vsn, vsn)

    quote do
      defmodule unquote(module_name) do
        @moduledoc """
        Generated Jido action for `#{unquote(resource)}.#{unquote(ash_action.name)}`.

        Wraps the Ash action; see the resource docs for semantics.
        """

        use Jido.Action, unquote(Macro.escape(action_use_opts))

        @resource unquote(resource)
        @ash_action unquote(ash_action.name)
        @ash_action_type unquote(ash_action.type)
        @jido_config unquote(Macro.escape(jido_action))
        @primary_key unquote(Macro.escape(primary_key))

        def on_before_validate_params(params) do
          {:ok, normalize_query_param_keys(params)}
        end

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
                  |> Ash.create!(maybe_add_notification_collection(ash_opts, @jido_config, :create))

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
                # Split query params from action arguments
                {query_opts, action_params} =
                  params
                  |> normalize_query_param_keys()
                  |> split_query_params(@jido_config)

                # Build query: apply action args, then static load, then dynamic query opts
                query =
                  @resource
                  |> Ash.Query.for_read(@ash_action, action_params, ash_opts)
                  |> maybe_load(@jido_config)
                  |> apply_query_opts(query_opts)

                result = Ash.read!(query, ash_opts)

                # Ash.read! returns a raw list, not {:ok, result}
                # Pass it directly to Mapper.wrap_result which will wrap it
                action_result = AshJido.Mapper.wrap_result(result, @jido_config)
                {action_result, empty_signal_meta(), false}

              :update ->
                primary_key = fetch_primary_key!(params, :update)
                update_params = drop_primary_key_params(params)

                # Load the record first
                record =
                  @resource
                  |> Ash.get!(primary_key, ash_opts)

                update_result =
                  record
                  |> Ash.Changeset.for_update(@ash_action, update_params, ash_opts)
                  |> Ash.update!(maybe_add_notification_collection(ash_opts, @jido_config, :update))

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
                primary_key = fetch_primary_key!(params, :destroy)
                destroy_params = drop_primary_key_params(params)

                # Load the record first
                record =
                  @resource
                  |> Ash.get!(primary_key, ash_opts)

                destroy_result =
                  record
                  |> Ash.Changeset.for_destroy(@ash_action, destroy_params, ash_opts)
                  |> Ash.destroy!(maybe_add_notification_collection(ash_opts, @jido_config, :destroy))

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

        defp fetch_primary_key!(params, action_type) do
          values =
            Map.new(@primary_key, fn key ->
              {key, fetch_param(params, key)}
            end)

          missing_keys =
            values
            |> Enum.filter(fn {_key, value} -> is_nil(value) end)
            |> Enum.map(fn {key, _value} -> key end)

          unless Enum.empty?(missing_keys) do
            raise ArgumentError, missing_primary_key_message(action_type, @primary_key)
          end

          case @primary_key do
            [key] -> Map.fetch!(values, key)
            _ -> values
          end
        end

        defp fetch_param(params, key) do
          case Map.fetch(params, key) do
            {:ok, value} -> value
            :error -> Map.get(params, to_string(key))
          end
        end

        defp drop_primary_key_params(params) do
          Enum.reduce(@primary_key, params, fn key, acc ->
            Map.drop(acc, [key, to_string(key)])
          end)
        end

        defp missing_primary_key_message(action_type, primary_key) do
          cond do
            action_type == :update and primary_key == [:id] ->
              "Update actions require an 'id' parameter"

            action_type == :destroy and primary_key == [:id] ->
              "Destroy actions require an 'id' parameter"

            true ->
              action_label = action_type |> Atom.to_string() |> String.capitalize()
              key_list = Enum.map_join(primary_key, ", ", &to_string/1)

              "#{action_label} actions require primary key parameter(s): #{key_list}"
          end
        end

        defp maybe_load(query, config) do
          case config.load do
            nil -> query
            load -> Ash.Query.load(query, load)
          end
        end

        @query_param_keys [:filter, :sort, :limit, :offset, :load]
        @valid_sort_directions [
          :asc,
          :desc,
          :asc_nils_first,
          :asc_nils_last,
          :desc_nils_first,
          :desc_nils_last
        ]
        @sort_directions_by_name Map.new(@valid_sort_directions, &{Atom.to_string(&1), &1})

        defp normalize_query_param_keys(params) do
          Enum.reduce(@query_param_keys, params, fn key, acc ->
            string_key = to_string(key)

            cond do
              Map.has_key?(acc, key) and Map.has_key?(acc, string_key) ->
                Map.delete(acc, string_key)

              Map.has_key?(acc, string_key) ->
                acc
                |> Map.put(key, Map.get(acc, string_key))
                |> Map.delete(string_key)

              true ->
                acc
            end
          end)
        end

        defp split_query_params(params, jido_config) do
          if jido_config.query_params? do
            {query_opts_map, action_params} = Map.split(params, @query_param_keys)

            query_opts =
              query_opts_map
              |> Enum.reject(fn {_k, v} -> is_nil(v) end)
              |> Map.new()
              |> enforce_max_page_size(jido_config)

            {query_opts, action_params}
          else
            {%{}, params}
          end
        end

        defp enforce_max_page_size(query_opts, jido_config) do
          case jido_config.max_page_size do
            nil ->
              query_opts

            max when is_integer(max) ->
              case Map.get(query_opts, :limit) do
                limit when is_integer(limit) and limit > max ->
                  Map.put(query_opts, :limit, max)

                _ ->
                  query_opts
              end
          end
        end

        defp apply_query_opts(query, query_opts) when map_size(query_opts) == 0, do: query

        defp apply_query_opts(query, query_opts) do
          Enum.reduce(query_opts, query, fn
            {:filter, filter_map}, q -> Ash.Query.filter_input(q, filter_map)
            {:sort, sort_val}, q -> Ash.Query.sort_input(q, normalize_sort_input(sort_val))
            {:limit, limit}, q -> Ash.Query.limit(q, limit)
            {:offset, offset}, q -> Ash.Query.offset(q, offset)
            {:load, load}, q -> Ash.Query.load(q, load)
            _, q -> q
          end)
        end

        defp normalize_sort_input(sort) when is_list(sort) do
          cond do
            Keyword.keyword?(sort) ->
              sort

            true ->
              Enum.flat_map(sort, fn
                %{} = entry ->
                  case Map.get(entry, :field) || Map.get(entry, "field") do
                    nil ->
                      []

                    field ->
                      direction =
                        entry
                        |> Map.get(:direction)
                        |> case do
                          nil -> Map.get(entry, "direction")
                          value -> value
                        end
                        |> normalize_sort_direction()

                      [{field, direction}]
                  end

                {field, direction} ->
                  [{field, normalize_sort_direction(direction)}]

                entry when is_binary(entry) or is_atom(entry) ->
                  [entry]

                _ ->
                  []
              end)
          end
        end

        defp normalize_sort_input(sort), do: sort

        defp normalize_sort_direction(direction) when direction in @valid_sort_directions,
          do: direction

        defp normalize_sort_direction(direction) when is_binary(direction),
          do: Map.get(@sort_directions_by_name, direction, :asc)

        defp normalize_sort_direction(_), do: :asc

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

  defp build_parameter_schema(resource, ash_action, jido_action, dsl_state) do
    case ash_action.type do
      :create ->
        # Create actions use accepted attributes plus action arguments
        accepted_attrs =
          accepted_attributes_to_schema(resource, ash_action, dsl_state, jido_action)

        action_args = action_args_to_schema(ash_action.arguments || [], jido_action)
        accepted_attrs ++ action_args

      :update ->
        # Update actions need primary key fields plus accepted attributes plus action arguments
        base = primary_key_to_schema(dsl_state, :update)

        accepted_attrs =
          accepted_attributes_to_schema(resource, ash_action, dsl_state, jido_action)

        action_args = action_args_to_schema(ash_action.arguments || [], jido_action)
        base ++ accepted_attrs ++ action_args

      :destroy ->
        # Destroy actions need primary key fields plus action arguments
        base = primary_key_to_schema(dsl_state, :destroy)
        action_args = action_args_to_schema(ash_action.arguments || [], jido_action)
        base ++ action_args

      _ ->
        # Read and custom actions use their declared arguments
        base_schema = action_args_to_schema(ash_action.arguments || [], jido_action)

        if ash_action.type == :read and jido_action.query_params? do
          base_schema ++ build_query_params_schema(jido_action)
        else
          base_schema
        end
    end
  end

  defp build_query_params_schema(jido_action) do
    max_page_doc =
      if jido_action.max_page_size do
        " Maximum: #{jido_action.max_page_size}."
      else
        ""
      end

    [
      filter: [
        type: :any,
        required: false,
        doc:
          "Filter results using Ash's filter input syntax. " <>
            "Simple equality: %{\"name\" => \"fred\"}. " <>
            "Operators: %{\"age\" => %{\"greater_than\" => 25}}. " <>
            "In: %{\"status\" => %{\"in\" => [\"active\", \"pending\"]}}. " <>
            "Only public attributes are accessible."
      ],
      sort: [
        type: :any,
        required: false,
        doc:
          "Sort results. JSON list: [%{\"field\" => \"name\", \"direction\" => \"asc\"}]. " <>
            "Keyword list: [name: :asc, age: :desc]. " <>
            "String: \"name,-age\" (minus prefix = descending)."
      ],
      limit: [
        type: :pos_integer,
        required: false,
        doc: "Maximum number of results to return.#{max_page_doc}"
      ],
      offset: [
        type: :non_neg_integer,
        required: false,
        doc: "Number of results to skip."
      ],
      load: [
        type: :any,
        required: false,
        doc:
          "Relationships/calculations to load. " <>
            "Examples: :author, [:author, :comments], [author: [:profile]]. " <>
            "Merged with any static load configured on the action."
      ]
    ]
  end

  defp accepted_attributes_to_schema(_resource, ash_action, dsl_state, jido_action) do
    # Get the list of accepted attribute names from the action
    accepted_names = ash_action.accept || []

    # Get all attributes from the resource
    all_attributes = Transformer.get_entities(dsl_state, [:attributes])

    # Filter to only accepted attributes and convert to schema entries
    accepted_names
    |> Enum.flat_map(fn attr_name ->
      attr = Enum.find(all_attributes, &(&1.name == attr_name))

      cond do
        is_nil(attr) ->
          []

        include_schema_input?(attr, jido_action) ->
          [{attr_name, attribute_to_nimble_options(attr)}]

        true ->
          []
      end
    end)
  end

  defp primary_key_fields(dsl_state) do
    dsl_state
    |> Transformer.get_entities([:attributes])
    |> Enum.filter(& &1.primary_key?)
    |> Enum.map(& &1.name)
  end

  defp primary_key_to_schema(dsl_state, action_type) do
    primary_key = primary_key_fields(dsl_state)
    all_attributes = Transformer.get_entities(dsl_state, [:attributes])

    Enum.map(primary_key, fn attr_name ->
      attr = Enum.find(all_attributes, &(&1.name == attr_name))

      opts =
        case attr do
          nil -> [type: :any]
          attr -> attribute_to_nimble_options(attr)
        end

      opts =
        opts
        |> Keyword.put(:required, true)
        |> Keyword.put(:doc, primary_key_doc(attr_name, action_type))

      {attr_name, opts}
    end)
  end

  defp primary_key_doc(attr_name, action_type) do
    action = action_type |> Atom.to_string() |> String.downcase()
    "Primary key field #{attr_name} of record to #{action}"
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

  defp action_args_to_schema(arguments, jido_action) do
    arguments
    |> Enum.filter(&include_schema_input?(&1, jido_action))
    |> Enum.map(fn arg ->
      {arg.name, TypeMapper.ash_type_to_nimble_options(arg.type, arg)}
    end)
  end

  defp include_schema_input?(_input, %{include_private?: true}), do: true

  defp include_schema_input?(%{public?: false}, _jido_action), do: false
  defp include_schema_input?(_input, _jido_action), do: true

  defp pluralize(word) do
    cond do
      String.ends_with?(word, "y") ->
        String.slice(word, 0..-2//1) <> "ies"

      String.ends_with?(word, ["s", "sh", "ch", "x", "z"]) ->
        word <> "es"

      true ->
        word <> "s"
    end
  end

  defp maybe_put_option(opts, _key, nil), do: opts
  defp maybe_put_option(opts, key, value), do: Keyword.put(opts, key, value)
end
