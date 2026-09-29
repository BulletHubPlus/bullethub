defmodule Bullet.Repo.Migrations.CreateCatalogAndIngest do
  use Ecto.Migration

  def change do
    execute "CREATE TYPE collection_kind AS ENUM ('course', 'series')",
            "DROP TYPE collection_kind"

    execute "CREATE TYPE media_kind AS ENUM ('movie', 'episode', 'lesson')",
            "DROP TYPE media_kind"

    execute(
      "CREATE TYPE media_asset_status AS ENUM ('uploading', 'processing', 'ready', 'failed')",
      "DROP TYPE media_asset_status"
    )

    create table(:collections) do
      add :kind, :collection_kind, null: false
      add :title, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :thumbnail_url, :string
      add :published_at, :utc_datetime_usec

      timestamps()
    end

    create unique_index(:collections, [:slug])
    create index(:collections, [:published_at])

    create table(:seasons) do
      add :collection_id, references(:collections, on_delete: :delete_all), null: false
      add :number, :integer, null: false
      add :title, :string

      timestamps()
    end

    create unique_index(:seasons, [:collection_id, :number])

    create table(:media) do
      add :kind, :media_kind, null: false
      add :collection_id, references(:collections, on_delete: :delete_all)
      add :season_id, references(:seasons, on_delete: :delete_all)
      add :position, :integer
      add :title, :string, null: false
      add :synopsis, :text
      add :thumbnail_url, :string
      add :intro_end_seconds, :integer
      add :published_at, :utc_datetime_usec

      timestamps()
    end

    create unique_index(:media, [:season_id, :position])
    create index(:media, [:collection_id])
    create index(:media, [:published_at])

    # PRD §9: a movie never belongs to a collection; episodes always do.
    create constraint(:media, :movie_without_collection,
             check:
               "(kind = 'movie' AND collection_id IS NULL AND season_id IS NULL) OR " <>
                 "(kind <> 'movie' AND collection_id IS NOT NULL AND season_id IS NOT NULL)"
           )

    create table(:media_assets) do
      add :media_id, references(:media, on_delete: :delete_all), null: false
      add :bunny_video_id, :string, null: false
      add :status, :media_asset_status, null: false
      add :duration_seconds, :integer
      add :encoded_resolutions, {:array, :string}, null: false, default: []
      add :storage_bytes, :bigint
      add :error, :string
      add :status_changed_at, :utc_datetime_usec, null: false

      timestamps()
    end

    create unique_index(:media_assets, [:media_id])
    create unique_index(:media_assets, [:bunny_video_id])
    create index(:media_assets, [:status, :status_changed_at])

    create table(:webhook_events) do
      add :provider, :string, null: false
      add :event_id, :string, null: false
      add :payload, :map, null: false
      add :processed_at, :utc_datetime_usec
      add :error, :string

      timestamps()
    end

    create unique_index(:webhook_events, [:provider, :event_id])
  end
end
