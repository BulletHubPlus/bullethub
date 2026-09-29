defmodule Bullet.Playback.Presence do
  @moduledoc """
  Live streams per account on topic `"streams:<user_id>"`, keyed by session id.
  Tracked by `BulletWeb.PlaybackChannel`; a closed tab or dead socket leaves
  automatically. CRDT-replicated across nodes, no Redis (PRD §10.3).
  """
  use Phoenix.Presence, otp_app: :bullet, pubsub_server: Bullet.PubSub

  def topic(user_id), do: "streams:#{user_id}"

  @spec session_ids(String.t()) :: MapSet.t(String.t())
  def session_ids(user_id), do: user_id |> topic() |> list() |> Map.keys() |> MapSet.new()
end
