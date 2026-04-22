defmodule AshJido.Generator do
  @moduledoc false

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

    schema = AshJido.Schema.build_parameter_schema(ash_action, jido_action, dsl_state)
    primary_key = AshJido.Schema.primary_key_fields(dsl_state)

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

        @ash_jido_spec %AshJido.ActionSpec{
          resource: unquote(resource),
          action_name: unquote(ash_action.name),
          action_type: unquote(ash_action.type),
          config: unquote(Macro.escape(jido_action)),
          primary_key: unquote(Macro.escape(primary_key)),
          generated_module: __MODULE__
        }

        def on_before_validate_params(params) do
          {:ok, AshJido.QueryParams.normalize_keys(params)}
        end

        def run(params, context) do
          AshJido.Runtime.run(@ash_jido_spec, params, context)
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
