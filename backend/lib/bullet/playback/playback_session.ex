defmodule Bullet.Playback.PlaybackSession do
  @moduledoc """
  One stream. `code` is the 6-char id burned into the watermark (RF06): any
  leaked frame traces back to this row, and from it to the account.
  """
  use Bullet.Schema

  @type t :: %__MODULE__{}

  schema "playback_sessions" do
    field :code, :string
    field :ip, :string
    field :started_at, :utc_datetime_usec
    field :joined_at, :utc_datetime_usec
    field :last_heartbeat_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :end_reason, :string

    belongs_to :user, Bullet.Accounts.User
    belongs_to :media, Bullet.Catalog.Media
    belongs_to :device, Bullet.Accounts.Device

    timestamps()
  end
end
