defmodule BulletWeb.Api.AuthController do
  use BulletWeb, :controller

  alias Bullet.Accounts
  alias BulletWeb.{AccessToken, ErrorResponse}
  alias BulletWeb.Api.UserJSON
  alias BulletWeb.Plugs.RateLimit

  action_fallback BulletWeb.Api.FallbackController

  @refresh_cookie "_bh_refresh"

  # Per IP, every attempt counts but the bar is loose: many Brazilian mobile
  # users share one address behind carrier-grade NAT. Per e-mail (PRD §10.1),
  # only *failed* attempts count - see login/2 - so signing in on several
  # devices in a row is never blocked.
  plug RateLimit,
       [name: "login", limit: 20, scale: :timer.minutes(1), by: [:ip]] when action == :login

  @login_failures_per_email 5
  @login_failure_window :timer.minutes(1)

  # Per-IP limits below assume carrier-grade NAT (many users, one address).
  plug RateLimit,
       [name: "register", limit: 20, scale: :timer.hours(1), by: [:ip]] when action == :register

  plug RateLimit,
       [name: "password", limit: 5, scale: :timer.hours(1), by: [{:ip, 20}, {:param, "email"}]]
       when action in [:forgot_password, :reset_password]

  # Every page load refreshes; the token is 256 random bits, so this only guards against flooding.
  plug RateLimit,
       [name: "refresh", limit: 300, scale: :timer.minutes(1), by: [:ip]] when action == :refresh

  def register(conn, params) do
    attrs = Map.take(params, ~w(email password name cpf))

    with {:ok, user} <- Accounts.register_user(attrs, &app_url("/confirmar-email/#{&1}")) do
      conn |> put_status(201) |> json(%{user: UserJSON.user(user)})
    end
  end

  def login(conn, params) do
    failures_key =
      "login_fail:" <> (params["email"] |> to_string() |> String.trim() |> String.downcase())

    if Bullet.RateLimit.get(failures_key, @login_failure_window) >= @login_failures_per_email do
      conn
      |> put_resp_header("retry-after", "60")
      |> ErrorResponse.send(
        429,
        "rate_limited",
        "Muitas tentativas. Tente novamente em instantes."
      )
    else
      do_login(conn, params, failures_key)
    end
  end

  defp do_login(conn, params, failures_key) do
    case Accounts.login(
           params["email"],
           params["password"],
           %{name: params["device_name"]},
           ctx(conn)
         ) do
      {:ok, session} ->
        respond_with_session(conn, session, 200)

      {:error, :suspended} ->
        ErrorResponse.send(conn, 403, "account_suspended", "Conta suspensa. Fale com o suporte.")

      {:error, :invalid_credentials} ->
        Bullet.RateLimit.inc(failures_key, @login_failure_window)
        ErrorResponse.send(conn, 401, "invalid_credentials", "E-mail ou senha incorretos.")
    end
  end

  def refresh(conn, _params) do
    conn = fetch_cookies(conn)

    with raw when is_binary(raw) <- conn.cookies[@refresh_cookie],
         {:ok, session} <- Accounts.refresh(raw, ctx(conn)) do
      respond_with_session(conn, session, 200)
    else
      _ ->
        conn
        |> delete_refresh_cookie()
        |> ErrorResponse.send(401, "unauthorized", "Sessão expirada. Entre novamente.")
    end
  end

  def logout(conn, _params) do
    conn = fetch_cookies(conn)
    if raw = conn.cookies[@refresh_cookie], do: Accounts.logout(raw)
    conn |> delete_refresh_cookie() |> send_resp(204, "")
  end

  def confirm(conn, %{"token" => token}) when is_binary(token) do
    with {:ok, user} <- Accounts.confirm_user(token) do
      json(conn, %{user: UserJSON.user(user)})
    end
  end

  def resend_confirmation(conn, _params) do
    with {:ok, _job} <-
           Accounts.resend_confirmation(
             conn.assigns.current_user,
             &app_url("/confirmar-email/#{&1}")
           ) do
      send_resp(conn, 202, "")
    end
  end

  def forgot_password(conn, %{"email" => email}) when is_binary(email) do
    :ok = Accounts.request_password_reset(email, &app_url("/redefinir-senha/#{&1}"))
    send_resp(conn, 202, "")
  end

  def reset_password(conn, %{"token" => token, "password" => password})
      when is_binary(token) and is_binary(password) do
    with {:ok, _user} <- Accounts.reset_password(token, %{password: password}) do
      conn |> delete_refresh_cookie() |> send_resp(204, "")
    end
  end

  defp respond_with_session(conn, %{user: user, device: device, refresh_token: refresh}, status) do
    conn
    |> put_resp_cookie(@refresh_cookie, refresh, cookie_opts())
    |> put_status(status)
    |> json(%{
      access_token: AccessToken.sign(user.id, device.id),
      expires_in: AccessToken.ttl(),
      device_id: device.id,
      user: UserJSON.user(user)
    })
  end

  defp delete_refresh_cookie(conn), do: delete_resp_cookie(conn, @refresh_cookie, cookie_opts())

  # Scoped to /api/auth so the cookie isn't sent on every request;
  # SameSite=Strict + same-origin SPA makes refresh CSRF-safe.
  defp cookie_opts do
    [
      http_only: true,
      secure: Application.get_env(:bullet, :secure_cookies, true),
      same_site: "Strict",
      path: "/api/auth",
      max_age: Application.fetch_env!(:bullet, :auth)[:refresh_token_ttl_days] * 86_400
    ]
  end

  defp app_url(path), do: BulletWeb.Endpoint.url() <> path

  defp ctx(conn) do
    %{
      ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
      user_agent: conn |> get_req_header("user-agent") |> List.first()
    }
  end
end
