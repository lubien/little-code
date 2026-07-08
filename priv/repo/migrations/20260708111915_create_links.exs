defmodule LitteCode.Repo.Migrations.CreateLinks do
  use Ecto.Migration

  def change do
    create table(:links) do
      add :hash, :string, null: false
      add :url, :text, null: false
      add :views, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:links, [:hash])
  end
end
