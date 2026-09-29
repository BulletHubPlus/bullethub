defmodule Bullet.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    execute(
      "CREATE TYPE user_role AS ENUM ('subscriber', 'support', 'editor', 'owner')",
      "DROP TYPE user_role"
    )

    create table(:users) do
      add :email, :citext, null: false
      add :password_hash, :string, null: false
      add :name, :string, null: false
      add :cpf_encrypted, :binary
      add :cpf_hash, :binary
      add :role, :user_role, null: false, default: "subscriber"
      add :confirmed_at, :utc_datetime_usec
      add :suspended_at, :utc_datetime_usec

      timestamps()
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:cpf_hash])

    create table(:devices) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :user_agent, :string
      add :last_seen_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps()
    end

    create index(:devices, [:user_id, :revoked_at])

    create table(:user_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :device_id, references(:devices, on_delete: :delete_all)
      # Only the SHA-256 of the token is stored; the raw value lives with the client.
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :citext
      # Set when a refresh token is rotated; presenting it again means reuse.
      add :used_at, :utc_datetime_usec

      timestamps(updated_at: false)
    end

    create unique_index(:user_tokens, [:context, :token])
    create index(:user_tokens, [:user_id])
    create index(:user_tokens, [:device_id])

    create table(:security_events) do
      add :user_id, references(:users, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :ip, :string
      add :user_agent, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(updated_at: false)
    end

    execute(
      "CREATE INDEX security_events_user_id_inserted_at_index ON security_events (user_id, inserted_at DESC)",
      "DROP INDEX security_events_user_id_inserted_at_index"
    )
  end
end
