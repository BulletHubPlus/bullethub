defmodule BulletWeb.AdminAuth do
  @moduledoc """
  Cookie-session auth for admin.bullethub.app (RF15). Independent from the SPA's
  bearer tokens: an admin session is an `admin_session` UserToken (12 h) whose
  raw value lives in the encrypted session cookie.
  """
  use BulletWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Bullet.Accounts

  @token_key "admin_token"

  def log_in(conn, user, raw_token) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(@token_key, raw_token)
    |> put_session(:live_socket_id, "admin_sessions:#{user.id}")
    |> redirect(to: ~p"/")
  end

  def log_out(conn) do
    Accounts.delete_admin_token(get_session(conn, @token_key))

    if socket_id = get_session(conn, :live_socket_id) do
      BulletWeb.Endpoint.broadcast(socket_id, "disconnect", %{})
    end

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> redirect(to: ~p"/login")
  end

  def fetch_admin(conn, _opts) do
    assign(conn, :current_admin, Accounts.get_staff_by_admin_token(get_session(conn, @token_key)))
  end

  def require_admin(%{assigns: %{current_admin: %{}}} = conn, _opts), do: conn

  def require_admin(conn, _opts) do
    conn |> redirect(to: ~p"/login") |> halt()
  end

  def redirect_if_admin(%{assigns: %{current_admin: %{}}} = conn, _opts),
    do: conn |> redirect(to: ~p"/") |> halt()

  def redirect_if_admin(conn, _opts), do: conn

  @doc """
  LiveView guards:

      on_mount {BulletWeb.AdminAuth, :require_staff}
      on_mount {BulletWeb.AdminAuth, {:require_role, [:owner, :editor]}}
  """
  def on_mount(:require_staff, _params, session, socket) do
    socket =
      Phoenix.Component.assign_new(socket, :current_admin, fn ->
        Accounts.get_staff_by_admin_token(session[@token_key])
      end)

    if socket.assigns.current_admin,
      do: {:cont, socket},
      else: {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
  end

  def on_mount({:require_role, roles}, _params, _session, socket) do
    if socket.assigns.current_admin.role in roles do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "Seu papel não tem acesso a esta área.")
       |> Phoenix.LiveView.redirect(to: ~p"/ingest")}
    end
  end
end
