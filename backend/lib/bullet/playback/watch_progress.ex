defmodule Bullet.Playback.WatchProgress do
  @moduledoc "Last position per (user, media). Upserted, not a history (PRD §9)."
  use Bullet.Schema

  @type t :: %__MODULE__{}

  schema "watch_progress" do
    field :position_seconds, :integer, default: 0
    field :completed, :boolean, default: false

    belongs_to :user, Bullet.Accounts.User
    belongs_to :media, Bullet.Catalog.Media

    timestamps()
  end
end
