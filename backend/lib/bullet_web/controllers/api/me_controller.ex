defmodule BulletWeb.Api.MeController do
  use BulletWeb, :controller

  alias Bullet.Accounts
  alias Bullet.Accounts.User
  alias BulletWeb.Api.UserJSON
  alias BulletWeb.ErrorResponse
  alias BulletWeb.Plugs.RateLimit

  action_fallback BulletWeb.Api.FallbackController

  plug RateLimit,
       [name: "account_danger", limit: 5, scale: :timer.minutes(10), by: [:user]]
       when action in [:export, :delete]

  def show(conn, _params) do
    user = conn.assigns.current_user

    json(conn, %{
      user: UserJSON.user(user),
      account: UserJSON.account(user),
      subscription: UserJSON.subscription(Bullet.Billing.access(user))
    })
  end

  @doc "LGPD art. 18 - portability: everything we hold, as a JSON download."
  def export(conn, _params) do
    conn
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="bullethub-meus-dados.json")
    )
    |> json(Accounts.export_user_data(conn.assigns.current_user))
  end

  @doc "LGPD art. 18 - erasure. Requires the current password again."
  def delete(conn, %{"password" => password}) when is_binary(password) do
    user = conn.assigns.current_user

    if User.valid_password?(user, password) do
      {:ok, _} = Accounts.erase_user(user)
      send_resp(conn, 204, "")
    else
      ErrorResponse.send(conn, 403, "invalid_password", "Senha incorreta.")
    end
  end

  def delete(conn, _params),
    do: ErrorResponse.send(conn, 403, "invalid_password", "Informe sua senha.")

  def devices(conn, _params) do
    current = conn.assigns.current_device_id
    devices = Accounts.list_devices(conn.assigns.current_user)
    json(conn, %{devices: Enum.map(devices, &UserJSON.device(&1, current))})
  end

  def revoke_device(conn, %{"id" => id}) do
    ctx = %{
      ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
      user_agent: conn |> get_req_header("user-agent") |> List.first()
    }

    with {:ok, _} <- Ecto.UUID.cast(id),
         :ok <- Accounts.revoke_device(conn.assigns.current_user, id, ctx) do
      send_resp(conn, 204, "")
    else
      :error -> {:error, :not_found}
      error -> error
    end
  end
end
