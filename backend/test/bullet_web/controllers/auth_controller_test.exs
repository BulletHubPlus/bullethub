defmodule BulletWeb.Api.AuthControllerTest do
  use BulletWeb.ConnCase, async: true

  import Bullet.AccountsFixtures
  import Ecto.Query

  defp login(conn, user, password \\ valid_password()) do
    post(conn, ~p"/api/auth/login", %{
      email: user.email,
      password: password,
      device_name: "Notebook"
    })
  end

  defp refresh_cookie(conn), do: conn.resp_cookies["_bh_refresh"]

  test "register returns the user without CPF", %{conn: conn} do
    attrs = valid_user_attributes()
    conn = post(conn, ~p"/api/auth/register", attrs)

    assert %{"user" => user} = json_response(conn, 201)
    assert user["email"] == attrs.email
    refute Map.has_key?(user, "cpf")
  end

  test "register validation errors use the standard envelope", %{conn: conn} do
    conn = post(conn, ~p"/api/auth/register", %{email: "x"})

    assert %{"error" => %{"code" => "validation_failed", "details" => %{"fields" => fields}}} =
             json_response(conn, 422)

    assert Map.has_key?(fields, "cpf")
  end

  test "login → access token + HttpOnly refresh cookie scoped to /api/auth", %{conn: conn} do
    user = user_fixture()
    conn = login(conn, user)

    assert %{"access_token" => token, "expires_in" => 900, "user" => %{"id" => id}} =
             json_response(conn, 200)

    assert id == user.id and is_binary(token)

    cookie = refresh_cookie(conn)
    assert cookie.http_only
    assert cookie.same_site == "Strict"
    assert cookie.path == "/api/auth"
  end

  test "wrong password → 401 invalid_credentials", %{conn: conn} do
    user = user_fixture()

    assert %{"error" => %{"code" => "invalid_credentials"}} =
             json_response(login(conn, user, "errada-errada-1"), 401)
  end

  test "login is rate limited per e-mail", %{conn: conn} do
    user = user_fixture()

    for i <- 1..5 do
      conn |> Map.put(:remote_ip, {198, 51, 100, i}) |> login(user, "errada-errada-1")
    end

    conn = conn |> Map.put(:remote_ip, {198, 51, 100, 99}) |> login(user)
    assert %{"error" => %{"code" => "rate_limited"}} = json_response(conn, 429)
    assert get_resp_header(conn, "retry-after") != []
  end

  test "successful logins never count against the per-e-mail limit", %{conn: conn} do
    user = user_fixture()

    for i <- 1..8 do
      assert json_response(conn |> Map.put(:remote_ip, {198, 51, 101, i}) |> login(user), 200)
    end
  end

  test "per IP the limit is looser (carrier-grade NAT) but still exists", %{conn: conn} do
    ip = {203, 0, 113, 77}

    statuses =
      for i <- 1..21,
          do:
            conn
            |> Map.put(:remote_ip, ip)
            |> post(~p"/api/auth/login", %{email: "u#{i}@x.com", password: "x"})
            |> Map.get(:status)

    assert Enum.take(statuses, 20) |> Enum.all?(&(&1 == 401))
    assert List.last(statuses) == 429
  end

  test "refresh rotates the cookie; the old cookie then kills the session", %{conn: conn} do
    user = user_fixture()
    c1 = refresh_cookie(login(conn, user)).value

    conn2 = conn |> put_req_cookie("_bh_refresh", c1) |> post(~p"/api/auth/refresh")
    assert %{"access_token" => _} = json_response(conn2, 200)
    c2 = refresh_cookie(conn2).value
    assert c2 != c1

    # Outside the 30 s grace window (see Accounts.rotate/1).
    Bullet.Repo.update_all(
      from(t in Bullet.Accounts.UserToken, where: t.user_id == ^user.id and not is_nil(t.used_at)),
      set: [used_at: DateTime.add(DateTime.utc_now(), -60, :second)]
    )

    reuse = build_conn() |> put_req_cookie("_bh_refresh", c1) |> post(~p"/api/auth/refresh")
    assert json_response(reuse, 401)

    after_reuse = build_conn() |> put_req_cookie("_bh_refresh", c2) |> post(~p"/api/auth/refresh")
    assert json_response(after_reuse, 401)
  end

  test "refresh without cookie → 401", %{conn: conn} do
    assert %{"error" => %{"code" => "unauthorized"}} =
             json_response(post(conn, ~p"/api/auth/refresh"), 401)
  end

  describe "authenticated routes" do
    setup %{conn: conn} do
      user = user_fixture()
      body = conn |> login(user) |> json_response(200)
      %{user: user, token: body["access_token"], device_id: body["device_id"]}
    end

    test "GET /api/me requires a bearer token", %{conn: conn, token: token, user: user} do
      assert json_response(get(conn, ~p"/api/me"), 401)

      assert %{"user" => %{"id" => id}} =
               conn
               |> put_req_header("authorization", "Bearer " <> token)
               |> get(~p"/api/me")
               |> json_response(200)

      assert id == user.id
    end

    test "API responses are no-store and carry a strict CSP", %{conn: conn, token: token} do
      conn = conn |> put_req_header("authorization", "Bearer " <> token) |> get(~p"/api/me")
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "default-src 'none'"
    end

    test "revoking the current device invalidates its access token at once", %{
      conn: conn,
      token: token,
      device_id: device_id
    } do
      authed = put_req_header(conn, "authorization", "Bearer " <> token)

      assert %{"devices" => [%{"id" => ^device_id, "current" => true}]} =
               authed |> get(~p"/api/me/devices") |> json_response(200)

      assert response(delete(authed, ~p"/api/me/devices/#{device_id}"), 204)
      assert json_response(get(authed, ~p"/api/me"), 401)
    end

    test "revoking an unknown or malformed id → 404", %{conn: conn, token: token} do
      authed = put_req_header(conn, "authorization", "Bearer " <> token)
      assert json_response(delete(authed, ~p"/api/me/devices/#{UUIDv7.generate()}"), 404)
      assert json_response(delete(authed, ~p"/api/me/devices/nope"), 404)
    end
  end

  test "logout clears the cookie and revokes the device", %{conn: conn} do
    user = user_fixture()
    c1 = refresh_cookie(login(conn, user)).value

    out = build_conn() |> put_req_cookie("_bh_refresh", c1) |> post(~p"/api/auth/logout")
    assert response(out, 204)
    assert refresh_cookie(out).max_age == 0

    assert json_response(
             build_conn() |> put_req_cookie("_bh_refresh", c1) |> post(~p"/api/auth/refresh"),
             401
           )
  end

  test "forgot password always answers 202", %{conn: conn} do
    assert response(post(conn, ~p"/api/auth/password/forgot", %{email: "ghost@example.com"}), 202)
  end
end
