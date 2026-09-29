defmodule Bullet.Repo.Migrations.AddTitleMetadata do
  use Ecto.Migration

  # Title-level metadata lives on `collections` (series/anime) and on `media`
  # (used for movies; episodes keep only synopsis/thumbnail).
  def change do
    execute "CREATE EXTENSION IF NOT EXISTS unaccent", ""

    for table <- [:collections, :media] do
      alter table(table) do
        add :original_title, :string
        add :release_year, :integer
        # Classificação indicativa (ClassInd): L, 10, 12, 14, 16, 18.
        add :age_rating, :string
        add :genres, {:array, :string}, null: false, default: []
        add :cast, {:array, :string}, null: false, default: []
        # Direção (filmes/séries) ou estúdio (anime).
        add :creators, {:array, :string}, null: false, default: []
        add :poster_url, :string
        add :backdrop_url, :string
      end

      create index(table, [:genres], using: :gin)
    end
  end
end
