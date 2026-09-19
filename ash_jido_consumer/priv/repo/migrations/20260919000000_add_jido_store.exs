defmodule AshJidoConsumer.Repo.Migrations.AddJidoStore do
  use Ecto.Migration

  def change do
    create table(:jido_store, primary_key: false) do
      add(:key, :binary, primary_key: true, null: false)
      add(:value, :binary, null: false)
      add(:write_token, :binary, null: false)
    end
  end
end
