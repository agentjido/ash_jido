defmodule AshJidoConsumer.Repo.Migrations.AddTenantNotes do
  use Ecto.Migration

  def change do
    create table(:tenant_notes, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:tenant_id, :text, null: false)
      add(:body, :text, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:tenant_notes, [:tenant_id]))
  end
end
