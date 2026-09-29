defmodule Bullet.Repo.Migrations.CreateMediaCaptions do
  use Ecto.Migration

  def change do
    create table(:media_captions) do
      add :media_id, references(:media, on_delete: :delete_all), null: false
      add :srclang, :string, null: false
      add :label, :string, null: false
      # WebVTT text. Bunny keeps its own copy for the embed; this one serves the
      # native engine and lets the admin list/replace tracks.
      add :content, :text, null: false

      timestamps()
    end

    create unique_index(:media_captions, [:media_id, :srclang])
  end
end
