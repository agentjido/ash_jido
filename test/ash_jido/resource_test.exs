defmodule AshJido.ResourceTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  describe "AshJido extension" do
    test "provides jido section" do
      # Check that the DSL section is available
      section = AshJido.Resource.Dsl.jido_section()
      assert section.name == :jido
      # action, all_actions, publish, publish_all
      assert length(section.entities) == 4
    end

    test "DSL entities are properly configured" do
      section = AshJido.Resource.Dsl.jido_section()

      action_entity = Enum.find(section.entities, &(&1.name == :action))
      assert action_entity != nil
      assert action_entity.target == AshJido.Resource.JidoAction

      publish_entity = Enum.find(section.entities, &(&1.name == :publish))
      assert publish_entity != nil
      assert publish_entity.target == AshJido.Publication
    end

    test "JidoAction struct has required fields" do
      jido_action = %AshJido.Resource.JidoAction{action: :test}
      assert jido_action.action == :test
      assert jido_action.output_map? == true
    end
  end
end
