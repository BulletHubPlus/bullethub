defmodule BulletWeb.UserSocket do
  @moduledoc """
  SPA socket. The access token travels in the `Sec-WebSocket-Protocol` header
  (`authToken` in phoenix.js), not in the URL, so it doesn't land in proxy logs.
  """
  use Phoenix.Socket

  require Logger

  alias Bullet.Accounts
  alias BulletWeb.AccessToken
  alias BulletWeb.Plugs.RemoteIp

  channel "user:*", BulletWeb.UserChannel
  channel "playback:*", BulletWeb.PlaybackChannel

  @impl true
  def connect(_params, socket, %{auth_token: token} = info) do
    with {:ok, %{user_id: user_id, device_id: device_id}} <- AccessToken.verify(token),
         {:ok, _user} <- Accounts.fetch_active_session(user_id, device_id) do
      {:ok,
       assign(socket,
         user_id: user_id,
         device_id: device_id,
         ip: peer_ip(info),
         user_agent: info[:user_agent]
       )}
    else
      error ->
        Logger.debug("socket refused: #{inspect(error)}")
        :error
    end
  end

  def connect(_params, _socket, connect_info) do
    Logger.debug("socket refused: no auth token in #{inspect(Map.keys(connect_info))}")
    :error
  end

  # Same rule as BulletWeb.Plugs.RemoteIp: trust the right-most X-Forwarded-For
  # entry only when the TCP peer is the proxy on the private network.
  defp peer_ip(info) do
    peer = get_in(info, [:peer_data, :address])

    forwarded =
      if peer && RemoteIp.private?(peer) do
        Enum.find_value(info[:x_headers] || [], fn
          {"x-forwarded-for", value} -> value |> String.split(",") |> List.last() |> String.trim()
          _ -> nil
        end)
      end

    forwarded || (peer && peer |> :inet.ntoa() |> to_string())
  end

  # Broadcasting "disconnect" here drops every socket of a revoked device (RF11).
  @impl true
  def id(socket), do: "device_socket:#{socket.assigns.device_id}"
end
