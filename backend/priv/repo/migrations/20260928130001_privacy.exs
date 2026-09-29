defmodule Bullet.Repo.Migrations.Privacy do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # LGPD erasure anonymizes in place (fiscal data must be kept 5 years).
      add :deleted_at, :utc_datetime_usec
    end

    # erase_user/1 unlinks streams from the person (PRD §12).
    execute "ALTER TABLE playback_sessions ALTER COLUMN user_id DROP NOT NULL",
            "ALTER TABLE playback_sessions ALTER COLUMN user_id SET NOT NULL"

    create index(:playback_sessions, [:started_at])
    create index(:security_events, [:inserted_at])
  end
end
