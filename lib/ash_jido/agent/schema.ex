defmodule AshJido.Agent.Schema do
  @moduledoc false

  alias Zoi.Types

  @scalar_types %{
    Types.Atom => :atom,
    Types.Boolean => :boolean,
    Types.Integer => :integer,
    Types.Float => :float,
    Types.Date => :date
  }

  @spec fields!(Zoi.schema()) :: keyword()
  def fields!(%Types.Map{fields: fields}) when is_list(fields) do
    Enum.map(fields, fn
      {name, schema} when is_atom(name) ->
        {name, field!(schema)}

      {name, _schema} ->
        raise ArgumentError, "expected an atom field name, got #{inspect(name)}"
    end)
  end

  def fields!(_schema), do: raise(ArgumentError, "expected an object schema with named fields")

  @spec field!(Zoi.schema()) :: keyword()
  def field!(%Types.Union{schemas: [%Types.Null{}, schema]}) do
    Keyword.put(field!(schema), :allow_nil?, true)
  end

  def field!(%{__struct__: module, meta: meta} = schema) do
    {type, constraints} = ash_type!(module, schema)
    [type: type, constraints: constraints, allow_nil?: meta.required == false or meta.default != nil]
  end

  defp ash_type!(module, _schema) when is_map_key(@scalar_types, module) do
    {Map.fetch!(@scalar_types, module), []}
  end

  defp ash_type!(Types.String, _schema), do: {:string, [allow_empty?: true, trim?: false]}

  defp ash_type!(Types.Enum, %Types.Enum{enum_type: :atom, values: values}) do
    {:atom, [one_of: Keyword.keys(values)]}
  end

  defp ash_type!(Types.Enum, %Types.Enum{enum_type: :binary, values: values}) do
    pattern = Enum.map_join(values, "|", fn {value, _} -> Regex.escape(value) end)
    {:string, [allow_empty?: true, trim?: false, match: Regex.compile!("\\A(?:" <> pattern <> ")\\z")]}
  end

  defp ash_type!(Types.Array, %Types.Array{inner: inner, prefix_items: []}) do
    {item_type, options} = Keyword.pop!(field!(inner), :type)
    {{:array, item_type}, [items: options[:constraints], nil_items?: options[:allow_nil?]]}
  end

  defp ash_type!(Types.Map, %Types.Map{fields: fields} = schema) when is_list(fields) do
    {:map, [fields: fields!(schema)]}
  end

  defp ash_type!(Types.Map, %Types.Map{fields: nil, key_type: nil, value_type: nil}), do: {:map, []}

  defp ash_type!(module, _schema),
    do: raise(ArgumentError, "unsupported Ash mapping for #{inspect(module)}")
end
