defmodule AshJido.RelationshipLoadTest do
  use ExUnit.Case, async: false

  defmodule Author do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
    end

    actions do
      defaults([:read, :destroy])

      create :create do
        accept([:name])
      end
    end
  end

  defmodule ArticleWithActionLoad do
    use Ash.Resource,
      domain: nil,
      extensions: [AshJido],
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
    end

    relationships do
      belongs_to(:author, Author, allow_nil?: false, public?: true)
    end

    actions do
      defaults([:read, :destroy])

      create :create do
        accept([:title, :author_id])
      end
    end

    jido do
      action(:create, name: "create_article_action_load")
      action(:read, name: "list_articles_action_load", load: [:author])

      action(:read,
        name: "list_articles_dynamic_load",
        module_name: AshJido.RelationshipLoadTest.ArticleWithDynamicLoad,
        allowed_loads: [:author]
      )
    end
  end

  defmodule IntegerAuthor do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      attribute(:id, :integer, primary_key?: true, allow_nil?: false, public?: true)
      attribute(:name, :string, allow_nil?: false, public?: true)
    end

    actions do
      defaults([:read])
    end
  end

  defmodule ArticleWithCustomSourceAttribute do
    use Ash.Resource,
      domain: nil,
      extensions: [AshJido],
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
    end

    relationships do
      belongs_to(:writer, IntegerAuthor,
        source_attribute: :writer_ref,
        attribute_type: :integer,
        allow_nil?: false,
        public?: true
      )
    end

    actions do
      create :create do
        accept([:title, :writer_ref])
      end
    end

    jido do
      action(:create, name: "create_article_custom_source_attribute")
    end
  end

  defmodule ArticleWithPrivateRelationshipSource do
    use Ash.Resource,
      domain: nil,
      extensions: [AshJido],
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
    end

    relationships do
      belongs_to(:author, Author, allow_nil?: false, public?: false)
    end

    actions do
      create :create do
        accept([:title, :author_id])
      end
    end

    jido do
      action(:create, name: "create_article_private_relationship_source")

      action(:create,
        name: "create_article_private_relationship_source_internal",
        module_name: AshJido.RelationshipLoadTest.ArticleWithPrivateRelationshipSource.InternalCreate,
        include_private?: true
      )
    end
  end

  defmodule ArticleWithAllActionsReadLoad do
    use Ash.Resource,
      domain: nil,
      extensions: [AshJido],
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
    end

    relationships do
      belongs_to(:author, Author, allow_nil?: false, public?: true)
    end

    actions do
      defaults([:read, :destroy])

      create :create do
        accept([:title, :author_id])
      end
    end

    jido do
      all_actions(only: [:create, :read], read_load: [:author])
    end
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource(Author)
      resource(IntegerAuthor)
      resource(ArticleWithActionLoad)
      resource(ArticleWithCustomSourceAttribute)
      resource(ArticleWithPrivateRelationshipSource)
      resource(ArticleWithAllActionsReadLoad)
    end
  end

  describe "relationship-aware reads" do
    test "create schema includes accepted belongs_to source attributes" do
      schema = ArticleWithActionLoad.Jido.Create.schema()

      assert schema[:title][:required] == true
      assert schema[:author_id][:type] == :string
      assert schema[:author_id][:required] == true

      all_actions_schema = ArticleWithAllActionsReadLoad.Jido.Create.schema()

      assert all_actions_schema[:author_id][:type] == :string
      assert all_actions_schema[:author_id][:required] == true
    end

    test "create schema uses custom belongs_to source attribute names and types" do
      schema = ArticleWithCustomSourceAttribute.Jido.Create.schema()

      assert schema[:writer_ref][:type] == :integer
      assert schema[:writer_ref][:required] == true
      refute Keyword.has_key?(schema, :writer_id)
    end

    test "create schema respects private belongs_to source attributes" do
      public_schema = ArticleWithPrivateRelationshipSource.Jido.Create.schema()
      internal_schema = ArticleWithPrivateRelationshipSource.InternalCreate.schema()

      refute Keyword.has_key?(public_schema, :author_id)
      assert internal_schema[:author_id][:type] == :string
      assert internal_schema[:author_id][:required] == true
    end

    test "action load applies static read relationship load" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{name: "Ada"}, domain: Domain)
        |> Ash.create!(domain: Domain)

      {:ok, _article} =
        ArticleWithActionLoad.Jido.Create.run(
          %{title: "Action Load", author_id: author.id},
          %{domain: Domain}
        )

      {:ok, %{result: articles}} = ArticleWithActionLoad.Jido.Read.run(%{}, %{domain: Domain})
      article = Enum.find(articles, &(&1[:title] == "Action Load"))

      assert is_map(article)
      assert article[:author][:id] == author.id
      assert article[:author][:name] == "Ada"
    end

    test "dynamic read load is constrained to allowlisted relationships" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{name: "Katherine"}, domain: Domain)
        |> Ash.create!(domain: Domain)

      {:ok, _article} =
        ArticleWithActionLoad.Jido.Create.run(
          %{title: "Dynamic Load", author_id: author.id},
          %{domain: Domain}
        )

      {:ok, %{result: articles}} =
        AshJido.RelationshipLoadTest.ArticleWithDynamicLoad.run(
          %{"load" => ["author"]},
          %{domain: Domain}
        )

      article = Enum.find(articles, &(&1[:title] == "Dynamic Load"))

      assert article[:author][:id] == author.id
      assert article[:author][:name] == "Katherine"

      assert {:error, error} =
               AshJido.RelationshipLoadTest.ArticleWithDynamicLoad.run(
                 %{load: [:not_allowed]},
                 %{domain: Domain}
               )

      assert error.message =~ "dynamic load"
      assert error.message =~ "not_allowed"
    end

    test "all_actions read_load applies static relationship load to generated read action" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{name: "Grace"}, domain: Domain)
        |> Ash.create!(domain: Domain)

      {:ok, _article} =
        ArticleWithAllActionsReadLoad.Jido.Create.run(
          %{title: "All Actions Load", author_id: author.id},
          %{domain: Domain}
        )

      {:ok, %{result: articles}} =
        ArticleWithAllActionsReadLoad.Jido.Read.run(%{}, %{domain: Domain})

      article = Enum.find(articles, &(&1[:title] == "All Actions Load"))

      assert is_map(article)
      assert article[:author][:id] == author.id
      assert article[:author][:name] == "Grace"
    end
  end
end
