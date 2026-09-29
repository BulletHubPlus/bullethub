defmodule BulletWeb.Plugs.RequireAuth do
  @moduledoc "Bearer access token → `conn.assigns.current_user` / `current_device_id`."
  @behaviour Plug

  import Plug.Conn
  require Logger
  alias Bullet.Accounts
  alias BulletWeb.{AccessToken, ErrorResponse}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{user_id: user_id, device_id: device_id}} <- AccessToken.verify(token),
         {:ok, user} <- Accounts.fetch_active_session(user_id, device_id) do
      Logger.metadata(user_id: user.id)

      conn
      |> assign(:current_user, user)
      |> assign(:current_device_id, device_id)
    else
      _ ->
        conn |> ErrorResponse.send(401, "unauthorized", "Sessão inválida ou expirada.") |> halt()
    end
  end
end
