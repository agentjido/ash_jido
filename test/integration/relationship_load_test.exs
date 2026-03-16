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
      attribute(:name, :string, allow_nil?: false)
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
      attribute(:title, :string, allow_nil?: false)
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
      attribute(:title, :string, allow_nil?: false)
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
      resource(ArticleWithActionLoad)
      resource(ArticleWithAllActionsReadLoad)
    end
  end

  describe "relationship-aware reads" do
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

      {:ok, articles} = ArticleWithActionLoad.Jido.Read.run(%{}, %{domain: Domain})
      article = Enum.find(articles, &(&1[:title] == "Action Load"))

      assert is_map(article)
      assert article[:author][:id] == author.id
      assert article[:author][:name] == "Ada"
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

      {:ok, articles} = ArticleWithAllActionsReadLoad.Jido.Read.run(%{}, %{domain: Domain})
      article = Enum.find(articles, &(&1[:title] == "All Actions Load"))

      assert is_map(article)
      assert article[:author][:id] == author.id
      assert article[:author][:name] == "Grace"
    end
  end
end
