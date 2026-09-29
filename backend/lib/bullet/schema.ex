defmodule Bullet.Schema do
  @moduledoc """
  Base for every Ecto schema: UUID v7 primary keys (time-ordered) and
  microsecond UTC timestamps, as required by PRD §9.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset

      @primary_key {:id, UUIDv7, autogenerate: true}
      @foreign_key_type UUIDv7
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
