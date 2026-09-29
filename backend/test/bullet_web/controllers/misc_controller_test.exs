defmodule BulletWeb.MiscControllerTest do
  use BulletWeb.ConnCase, async: true

  test "GET /health checks DB and jobs", %{conn: conn} do
    assert %{"status" => "ok", "checks" => %{"database" => true}} =
             json_response(get(conn, ~p"/health"), 200)
  end

  test "unknown API route → JSON 404, not the SPA", %{conn: conn} do
    assert %{"error" => %{"code" => "not_found"}} = json_response(get(conn, "/api/nope"), 404)
  end

  test "unknown app route serves the SPA shell with a strict CSP", %{conn: conn} do
    conn = get(conn, "/qualquer/rota")
    assert conn.status in [200, 503]
    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "frame-src https://iframe.mediadelivery.net"
    assert csp =~ "frame-ancestors 'none'"
  end

  describe "PWA files at the root" do
    @app Application.app_dir(:bullet, "priv/static/app")

    @tag skip:
           not File.exists?(Path.join(Application.app_dir(:bullet, "priv/static/app"), "sw.js"))
    test "manifest and service worker are served from / with revalidation", %{conn: conn} do
      conn = get(conn, "/manifest.webmanifest")
      assert conn.status == 200
      assert [ct] = get_resp_header(conn, "content-type")
      assert ct =~ "application/manifest+json"
      assert %{"start_url" => _, "icons" => [_ | _]} = Jason.decode!(conn.resp_body)

      sw = get(build_conn(), "/sw.js")
      assert sw.status == 200
      assert get_resp_header(sw, "cache-control") == ["no-cache"]
      assert File.exists?(Path.join(@app, "icons/icon-512.png"))
    end
  end
end
