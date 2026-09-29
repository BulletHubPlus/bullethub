defmodule Bullet.Repo.Migrations.CreateBillingAndPlayback do
  use Ecto.Migration

  def change do
    execute(
      "CREATE TYPE subscription_status AS ENUM ('trialing', 'active', 'past_due', 'canceled')",
      "DROP TYPE subscription_status"
    )

    create table(:plans) do
      add :slug, :string, null: false
      add :name, :string, null: false
      # Prices are a pending PO decision (PRD §15); null until set.
      add :price_cents, :integer
      add :max_streams, :integer, null: false
      add :active, :boolean, null: false, default: true

      timestamps()
    end

    create unique_index(:plans, [:slug])

    # PRD §6 RF07: Básico 1, Padrão 2, Família 4. `max_streams` is the single source.
    execute(
      """
      INSERT INTO plans (id, slug, name, max_streams, inserted_at, updated_at) VALUES
        (gen_random_uuid(), 'basico', 'Básico', 1, now(), now()),
        (gen_random_uuid(), 'padrao', 'Padrão', 2, now(), now()),
        (gen_random_uuid(), 'familia', 'Família', 4, now(), now())
      """,
      ""
    )

    create table(:subscriptions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :plan_id, references(:plans, on_delete: :restrict), null: false
      add :status, :subscription_status, null: false
      add :gateway, :string, null: false
      add :gateway_ref, :string
      add :current_period_end, :utc_datetime_usec, null: false

      timestamps()
    end

    create unique_index(:subscriptions, [:gateway_ref])
    create index(:subscriptions, [:user_id, :status])

    create table(:watch_progress) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :media_id, references(:media, on_delete: :delete_all), null: false
      add :position_seconds, :integer, null: false, default: 0
      add :completed, :boolean, null: false, default: false

      timestamps()
    end

    create unique_index(:watch_progress, [:user_id, :media_id])

    execute(
      "CREATE INDEX watch_progress_user_id_updated_at_index ON watch_progress (user_id, updated_at DESC)",
      "DROP INDEX watch_progress_user_id_updated_at_index"
    )

    create table(:playback_sessions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :media_id, references(:media, on_delete: :nilify_all)
      add :device_id, references(:devices, on_delete: :nilify_all)
      add :code, :string, size: 6, null: false
      add :ip, :string
      add :started_at, :utc_datetime_usec, null: false
      add :joined_at, :utc_datetime_usec
      add :last_heartbeat_at, :utc_datetime_usec
      add :ended_at, :utc_datetime_usec
      add :end_reason, :string

      timestamps()
    end

    create unique_index(:playback_sessions, [:code])
    create index(:playback_sessions, [:user_id, :ended_at])
  end
end
