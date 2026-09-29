defmodule Bullet.Repo.Migrations.ReplaceCoursesWithAnime do
  @moduledoc """
  Product decision (2026-09-28): no courses. Collections are series or anime,
  both season → episode, so `lesson` disappears from media_kind.
  """
  use Ecto.Migration

  def up do
    execute "ALTER TYPE collection_kind RENAME VALUE 'course' TO 'anime'"
    execute "UPDATE media SET kind = 'episode' WHERE kind = 'lesson'"

    # Postgres can't drop an enum value: swap the type. The check constraint
    # references the column type, so it is dropped and recreated around it.
    drop constraint(:media, :movie_without_collection)
    execute "ALTER TYPE media_kind RENAME TO media_kind_old"
    execute "CREATE TYPE media_kind AS ENUM ('movie', 'episode')"
    execute "ALTER TABLE media ALTER COLUMN kind TYPE media_kind USING kind::text::media_kind"
    execute "DROP TYPE media_kind_old"
    create_movie_constraint()
  end

  def down do
    drop constraint(:media, :movie_without_collection)
    execute "ALTER TYPE media_kind ADD VALUE 'lesson'"
    execute "ALTER TYPE collection_kind RENAME VALUE 'anime' TO 'course'"
    create_movie_constraint()
  end

  defp create_movie_constraint do
    create constraint(:media, :movie_without_collection,
             check:
               "(kind = 'movie' AND collection_id IS NULL AND season_id IS NULL) OR " <>
                 "(kind <> 'movie' AND collection_id IS NOT NULL AND season_id IS NOT NULL)"
           )
  end
end
