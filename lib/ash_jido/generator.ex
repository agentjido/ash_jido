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
    module_name = build_module_name(resource, jido_action, ash_action)
    module_ast = build_module_ast(resource, ash_action, jido_action, module_name)

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

  defp build_module_ast(resource, ash_action, jido_action, module_name) do
    action_name = jido_action.name || build_default_action_name(resource, ash_action)

    description =
      jido_action.description || ash_action.description || "Ash action: #{ash_action.name}"

    # Build input schema
    schema = build_parameter_schema(ash_action)

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
          domain = context[:domain]

          unless domain do
            raise ArgumentError,
                  "AshJido: :domain must be provided in context for #{inspect(@resource)}.#{@ash_action}"
          end

          actor = context[:actor]
          tenant = context[:tenant]

          # Execute the Ash action
          try do
            case unquote(ash_action.type) do
              :create ->
                result =
                  @resource
                  |> Ash.Changeset.for_create(@ash_action, params,
                    actor: actor,
                    tenant: tenant,
                    domain: domain
                  )
                  |> Ash.create!(domain: domain)

                {:ok, result} |> AshJido.Mapper.wrap_result(@jido_config)

              :read ->
                result =
                  @resource
                  |> Ash.Query.for_read(@ash_action, params,
                    actor: actor,
                    tenant: tenant,
                    domain: domain
                  )
                  |> Ash.read!(domain: domain)

                {:ok, result} |> AshJido.Mapper.wrap_result(@jido_config)

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
                  |> Ash.get!(record_id, domain: domain, actor: actor, tenant: tenant)

                # Update the record
                result =
                  record
                  |> Ash.Changeset.for_update(@ash_action, update_params,
                    actor: actor,
                    tenant: tenant,
                    domain: domain
                  )
                  |> Ash.update!(domain: domain)

                {:ok, result} |> AshJido.Mapper.wrap_result(@jido_config)

              :destroy ->
                # Load the record to destroy using its primary key
                record_id = Map.get(params, :id) || Map.get(params, "id")

                unless record_id do
                  raise ArgumentError, "Destroy actions require an 'id' parameter"
                end

                # Load the record first
                record =
                  @resource
                  |> Ash.get!(record_id, domain: domain, actor: actor, tenant: tenant)

                # Destroy the record
                result =
                  record
                  |> Ash.Changeset.for_destroy(@ash_action, %{},
                    actor: actor,
                    tenant: tenant,
                    domain: domain
                  )
                  |> Ash.destroy!(domain: domain)

                {:ok, result} |> AshJido.Mapper.wrap_result(@jido_config)

              :action ->
                result =
                  @resource
                  |> Ash.ActionInput.for_action(@ash_action, params,
                    actor: actor,
                    tenant: tenant,
                    domain: domain
                  )
                  |> Ash.run_action!()

                {:ok, result} |> AshJido.Mapper.wrap_result(@jido_config)
            end
          rescue
            error ->
              jido_error = AshJido.Error.from_ash(error)
              {:error, jido_error}
          end
        end
      end
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

  defp build_parameter_schema(ash_action) do
    case ash_action.type do
      :update ->
        # Update actions need an id field plus action arguments
        base = [id: [type: :string, required: true, doc: "ID of record to update"]]
        base ++ action_args_to_schema(ash_action.arguments || [])

      :destroy ->
        # Destroy actions just need an id
        [id: [type: :string, required: true, doc: "ID of record to destroy"]]

      _ ->
        # Create, read, and custom actions use their declared arguments
        action_args_to_schema(ash_action.arguments || [])
    end
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
