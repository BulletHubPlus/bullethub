defmodule BulletWeb.Api.MeControllerTest do
  use BulletWeb.ConnCase, async: true

  import Bullet.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture(%{cpf: "111.444.777-35"})
    {:ok, %{device: d}} = Bullet.Accounts.login(user.email, valid_password(), %{})

    %{
      user: user,
      conn:
        put_req_header(
          conn,
          "authorization",
          "Bearer " <> BulletWeb.AccessToken.sign(user.id, d.id)
        )
    }
  end

  test "GET /api/me shows the CPF masked only", %{conn: conn} do
    body = conn |> get(~p"/api/me") |> json_response(200)
    assert body["account"]["cpf_masked"] == "111.***.***-35"
    refute Jason.encode!(body) =~ "11144477735"
  end

  test "GET /api/me/export downloads JSON", %{conn: conn, user: user} do
    conn = get(conn, ~p"/api/me/export")
    assert %{"account" => %{"email" => email}} = json_response(conn, 200)
    assert email == user.email
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "attachment"
  end

  test "DELETE /api/me needs the right password, then the session is gone", %{conn: conn} do
    assert %{"error" => %{"code" => "invalid_password"}} =
             conn |> delete(~p"/api/me", %{password: "errada-errada-9"}) |> json_response(403)

    assert response(delete(conn, ~p"/api/me", %{password: valid_password()}), 204)
    assert json_response(get(conn, ~p"/api/me"), 401)
  end
end
