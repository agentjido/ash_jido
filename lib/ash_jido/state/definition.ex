defmodule AshJido.State.Definition do
  @moduledoc false

  alias Ash.Resource.{Change.OptimisticLock, Info}
  alias Ash.Resource.Change.ManageRelationship
  alias AshJido.State.Projection
  alias Jido.Joi

  @doc false
  @spec compile!(module(), keyword(), Macro.Env.t()) :: {Jido.Joi.schema(), map()}
  def compile!(resource, opts, env) do
    unless is_atom(resource) and match?({:module, ^resource}, Code.ensure_compiled(resource)) and
             Info.resource?(resource) do
      error!(env, "#{inspect(resource)} must be a compiled Ash resource")
    end

    allowed = [:fields, :read_only, :id, :read, :update, :version, :actor, :load, :codecs, :arguments]

    unless Keyword.keyword?(opts) and Enum.uniq(Keyword.keys(opts)) == Keyword.keys(opts) and
             Keyword.keys(opts) -- allowed == [] do
      error!(env, "ash requires unique supported keyword options")
    end

    key = Info.primary_key(resource)

    if key == [] or Keyword.get(opts, :id, :primary_key) != :primary_key,
      do: error!(env, "ash requires id: :primary_key and an Ash primary key")

    version = Keyword.get(opts, :version, :version)

    unless match?(%{type: Ash.Type.Integer, allow_nil?: false}, Info.attribute(resource, version)) do
      error!(env, "ash version #{inspect(version)} must be a required integer attribute")
    end

    read = action!(resource, opts[:read] || primary_read(resource, env), :read, env)
    update = action!(resource, opts[:update], :update, env)

    if read.manual != nil or read.modify_query != nil,
      do: error!(env, "ash state read must support the resource row filter and lock")

    unless is_nil(update.manual) and Enum.any?(update.changes, &locks_version?(&1, version)) do
      error!(env, "ash update requires an unconditional optimistic_lock(#{inspect(version)}) change")
    end

    writable = fields!(opts[:fields], :fields, env)
    read_only = fields!(Keyword.get(opts, :read_only, []), :read_only, env)
    reserved = [version, Info.multitenancy_attribute(resource) | key]

    if Enum.any?(writable, &(&1 in reserved or &1 in read_only)) do
      error!(env, "ash writable fields overlap with the primary key, version, tenant, or read_only fields")
    end

    if bad = Enum.find(writable, &(is_nil(Info.attribute(resource, &1)) or &1 not in update.accept)) do
      error!(env, "ash field #{inspect(bad)} is not an attribute accepted by #{inspect(update.name)}")
    end

    fields = Enum.uniq(writable ++ read_only ++ [version])
    codecs = indexed_options!(opts[:codecs], fields -- [version], :codecs, env)
    actor = opts[:actor]
    if actor != nil and not mfa?(actor), do: error!(env, "ash actor must be a module/function/arguments tuple")

    arguments = indexed_options!(opts[:arguments], Enum.map(update.arguments, & &1.name), :arguments, env)

    if Enum.any?(update.arguments, &(&1.name in writable)),
      do: error!(env, "ash update action arguments must have names distinct from writable fields")

    unless Enum.all?(arguments, fn {_name, field} -> field in writable end),
      do: error!(env, "ash arguments must map to writable state fields")

    arguments_required = Enum.reject(update.arguments, &(&1.allow_nil? or &1.default != nil))

    if Enum.any?(arguments_required, &(not Map.has_key?(arguments, &1.name))),
      do: error!(env, "ash update arguments without defaults must be mapped in arguments:")

    schema = Map.new(fields, &{&1, field_schema!(resource, &1, codecs, env)})
    load = Keyword.get(opts, :load, [])

    unless is_list(load) and Jido.Codec.Term.valid?(load),
      do: error!(env, "ash load must be a portable list of Ash loads")

    descriptor = %{
      resource: resource,
      touched_resources: touched_resources(resource, update),
      key: key,
      version: version,
      read: read.name,
      update: update.name,
      fields: fields,
      writable: writable,
      actor: actor,
      load: load,
      codecs: codecs,
      arguments: arguments
    }

    {Joi.object(schema), descriptor}
  end

  defp locks_version?(%{change: {OptimisticLock, opts}, where: []}, version), do: opts[:attribute] == version
  defp locks_version?(_change, _version), do: false

  defp touched_resources(resource, update) do
    managed =
      for %{change: {ManageRelationship, options}} <- update.changes ++ Info.changes(resource, :update),
          relationship = Info.relationship(resource, options[:relationship]),
          related <- [relationship.destination, Map.get(relationship, :through)],
          related != nil do
        related
      end

    Enum.uniq(update.touches_resources ++ managed)
  end

  defp primary_read(resource, env) do
    case Info.primary_action(resource, :read) do
      %{name: name} -> name
      nil -> error!(env, "ash requires a named read action")
    end
  end

  defp action!(resource, name, type, env) do
    Info.action(resource, name, type) || error!(env, "ash requires a valid #{type} action, got #{inspect(name)}")
  end

  defp fields!(values, option, env) do
    if is_list(values) and Enum.all?(values, &is_atom/1) and Enum.uniq(values) == values,
      do: values,
      else: error!(env, "ash #{option} must be a list of unique field names")
  end

  defp indexed_options!(nil, _names, _option, _env), do: %{}

  defp indexed_options!(value, names, option, env) do
    unless Keyword.keyword?(value) and Enum.uniq(Keyword.keys(value)) == Keyword.keys(value) and
             Keyword.keys(value) -- names == [] do
      error!(env, "ash #{option} must be unique options for declared fields or arguments")
    end

    Map.new(value)
  end

  defp field_schema!(resource, field, codecs, env) do
    attribute = Info.attribute(resource, field)
    codec = Map.get(codecs, field)

    if codec != nil and
         (not is_atom(codec) or not match?({:module, ^codec}, Code.ensure_compiled(codec)) or
            not function_exported?(codec, :encode, 1) or not function_exported?(codec, :decode, 1)) do
      error!(env, "ash codec for #{inspect(field)} must implement encode/1 and decode/1")
    end

    cond do
      attribute != nil and codec == nil and Ash.Type.embedded_type?(attribute.type) ->
        error!(env, "ash embedded field #{inspect(field)} requires a state codec")

      attribute != nil ->
        :ok

      Info.calculation(resource, field) || Info.aggregate(resource, field) ->
        :ok

      Info.relationship(resource, field) && codec != nil ->
        :ok

      true ->
        error!(env, "ash field #{inspect(field)} is unknown or requires a relationship codec")
    end

    Joi.any()
    |> Joi.refine({Projection, :check, [resource, field, codec]})
    |> Joi.required()
  end

  defp mfa?({module, function, args}),
    do: is_atom(module) and is_atom(function) and is_list(args) and Jido.Codec.Term.valid?(args)

  defp mfa?(_term), do: false

  defp error!(env, message), do: raise(CompileError, file: env.file, line: env.line, description: message)
end
