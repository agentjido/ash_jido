defmodule AshJidoConsumer.Repo.Migrations.CreateConsumerTables do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS \"pgcrypto\"")

    create table(:users, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:name, :text, null: false)
      add(:email, :text, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:users, [:email], name: "users_unique_email_index"))

    create table(:authors, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:name, :text, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create table(:posts, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:title, :text, null: false)
      add(:author_id, references(:authors, on_delete: :delete_all, type: :uuid), null: false)

      timestamps(type: :utc_datetime_usec)
    end
  end
end
