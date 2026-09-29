defmodule BulletWeb.UserChannel do
  @moduledoc """
  `user:<user_id>` - joined by every logged-in device. Server → client only:
  `progress_updated`, `device_revoked`, `subscription_changed` (PRD §10.2).
  """
  use BulletWeb, :channel

  @impl true
  def join("user:" <> user_id, _payload, socket) do
    if user_id == socket.assigns.user_id do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end
end
