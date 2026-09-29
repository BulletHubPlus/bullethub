defmodule Mix.Tasks.Bullet.E2e.Setup do
  @shortdoc "Recreates the E2E database and seeds it (refuses anything not named *_e2e)"
  @moduledoc """
      DB_NAME=bullet_e2e mix bullet.e2e.setup

  Drops, creates, migrates and seeds the database named by `DB_NAME`. Refuses
  to run unless the name ends in `_e2e`, so it can never wipe the dev database.
  """
  use Mix.Task

  @impl true
  def run(_args) do
    name = System.get_env("DB_NAME") || ""

    unless String.ends_with?(name, "_e2e") do
      Mix.raise("DB_NAME must end in _e2e (got #{inspect(name)}); refusing to drop it")
    end

    for task <- ["ecto.drop", "ecto.create", "ecto.migrate"], do: Mix.Task.run(task, ["--quiet"])
    Mix.Task.run("run", ["priv/repo/e2e_seeds.exs"])
  end
end
