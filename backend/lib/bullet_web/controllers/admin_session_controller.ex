defmodule BulletWeb.AdminSessionController do
  use BulletWeb, :controller

  alias Bullet.Accounts
  alias BulletWeb.AdminAuth
  alias BulletWeb.Plugs.RateLimit

  plug RateLimit,
       [name: "admin_login", limit: 5, scale: :timer.minutes(1), by: [:ip, {:param, "email"}]]
       when action == :create

  def new(conn, _params) do
    render(conn, :new,
      form: Phoenix.Component.to_form(%{"email" => ""}, as: :session),
      error: nil
    )
  end

  def create(conn, %{"session" => %{"email" => email, "password" => password}}) do
    ctx = %{
      ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
      user_agent: conn |> get_req_header("user-agent") |> List.first()
    }

    case Accounts.admin_login(email, password, ctx) do
      {:ok, user, raw} ->
        AdminAuth.log_in(conn, user, raw)

      {:error, :invalid_credentials} ->
        conn
        |> put_status(401)
        |> render(:new,
          form: Phoenix.Component.to_form(%{"email" => email}, as: :session),
          error: "Credenciais inválidas ou conta sem acesso ao painel."
        )
    end
  end

  def delete(conn, _params), do: AdminAuth.log_out(conn)
end
