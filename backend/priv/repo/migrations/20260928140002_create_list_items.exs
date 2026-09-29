defmodule Bullet.Repo.Migrations.CreateListItems do
  use Ecto.Migration

  def change do
    create table(:list_items) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :collection_id, references(:collections, on_delete: :delete_all)
      add :media_id, references(:media, on_delete: :delete_all)

      timestamps(updated_at: false)
    end

    create constraint(:list_items, :exactly_one_title,
             check: "(collection_id IS NULL) <> (media_id IS NULL)"
           )

    create unique_index(:list_items, [:user_id, :collection_id],
             where: "collection_id IS NOT NULL"
           )

    create unique_index(:list_items, [:user_id, :media_id], where: "media_id IS NOT NULL")
    create index(:list_items, [:user_id, :inserted_at])
  end
end
