defmodule AshJido.ToolsTest do
  use ExUnit.Case, async: true

  alias AshJido.Test.{Domain, Post, User}

  describe "actions/1" do
    test "returns generated action modules for a resource" do
      actions = AshJido.Tools.actions(User)

      assert User.Jido.Register in actions
      assert User.Jido.Read in actions
      assert User.Jido.Deactivate in actions
    end

    test "returns generated action modules for a domain" do
      actions = AshJido.Tools.actions(Domain)

      assert User.Jido.Register in actions
      assert User.Jido.Read in actions
      assert Post.Jido.Create in actions
      assert Post.Jido.Publish in actions
    end

    test "returns an empty list for non-ash modules" do
      assert AshJido.Tools.actions(Enum) == []
    end
  end

  describe "tools/1" do
    test "returns callable tool definitions for generated actions" do
      tools = AshJido.Tools.tools(User)

      create_tool = Enum.find(tools, &(&1.name == "create_user"))

      assert create_tool != nil
      assert is_binary(create_tool.description)
      assert is_map(create_tool.parameters_schema)
      assert is_function(create_tool.function, 2)

      assert {:ok, json} =
               create_tool.function.(
                 %{"name" => "Tool User", "email" => "tool-user@example.com"},
                 %{domain: Domain}
               )

      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["name"] == "Tool User"
      assert decoded["email"] == "tool-user@example.com"
    end
  end
end
