defmodule LitteCode.Repo.Migrations.AddSlugToLinks do
  use Ecto.Migration

  def change do
    alter table(:links) do
      add :slug, :string
    end

    # Unique among links that *have* a slug. Most links won't have one,
    # so a partial index keeps the on-disk footprint tiny.
    create unique_index(:links, [:slug], where: "slug IS NOT NULL")
  end
end
