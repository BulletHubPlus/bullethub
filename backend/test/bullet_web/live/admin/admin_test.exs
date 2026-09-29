defmodule BulletWeb.Admin.AdminTest do
  use BulletWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bullet.AccountsFixtures
  import Bullet.CatalogFixtures

  alias Bullet.{Accounts, Catalog, Ingest}

  defp admin_conn(conn), do: %{conn | host: "admin.localhost"}

  defp staff(role) do
    user = user_fixture()
    {:ok, user} = Accounts.set_role(user, role)
    user
  end

  defp log_in(conn, user) do
    {:ok, _, raw} = Accounts.admin_login(user.email, valid_password())
    conn |> admin_conn() |> init_test_session(%{"admin_token" => raw})
  end

  describe "login" do
    test "staff logs in; subscriber gets the same generic error", %{conn: conn} do
      editor = staff(:editor)

      conn =
        conn
        |> admin_conn()
        |> post("/login", %{session: %{email: editor.email, password: valid_password()}})

      assert redirected_to(conn) == "/"

      subscriber = user_fixture()

      conn =
        build_conn()
        |> admin_conn()
        |> post("/login", %{session: %{email: subscriber.email, password: valid_password()}})

      assert html_response(conn, 401) =~ "Credenciais inválidas"
    end

    test "panel redirects to login when signed out", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(admin_conn(conn), "/")
    end

    test "logout invalidates the session token", %{conn: conn} do
      conn = log_in(conn, staff(:owner))
      conn = delete(conn, "/logout")
      assert redirected_to(conn) == "/login"

      assert {:error, {:redirect, %{to: "/login"}}} =
               live(build_conn() |> admin_conn() |> recycle_session(conn), "/")
    end
  end

  defp recycle_session(new_conn, old_conn) do
    init_test_session(new_conn, Plug.Conn.get_session(old_conn))
  end

  describe "roles (RF15)" do
    test "support can see ingest but not the catalog", %{conn: conn} do
      conn = log_in(conn, staff(:support))
      assert {:ok, _view, _html} = live(conn, "/ingest")
      assert {:error, {:redirect, %{to: "/ingest"}}} = live(conn, "/")
    end
  end

  describe "catalog flow" do
    setup %{conn: conn}, do: %{conn: log_in(conn, staff(:editor))}

    test "create a collection and a season", %{conn: conn} do
      {:ok, view, _} = live(conn, "/colecoes/nova")

      {:error, {:live_redirect, %{to: "/colecoes/" <> id}}} =
        view
        |> form("#collection-form", collection: %{kind: "series", title: "Nova Série"})
        |> render_submit()

      {:ok, view, _} = live(conn, "/colecoes/#{id}")
      view |> form("#season-form", season: %{number: 1}) |> render_submit()
      assert has_element?(view, "#season-form")
      assert [_] = Catalog.get_collection!(id).seasons
    end

    test "media page: simulated upload → ready → publish, with live status", %{conn: conn} do
      movie = movie_fixture(title: "Filme LV")
      {:ok, view, _} = live(conn, "/midias/#{movie.id}")

      assert has_element?(view, "#simulate")
      assert has_element?(view, "#publish[disabled]")

      view |> element("#simulate") |> render_click()
      assert has_element?(view, "#asset-ready")

      view |> element("#publish") |> render_click()
      assert has_element?(view, "#unpublish")
      assert Catalog.get_media!(movie.id).published_at
    end

    test "status changes from a webhook reach an open ingest page (RF10)", %{conn: conn} do
      movie = movie_fixture(title: "Ao Vivo")
      asset = with_asset(movie, :processing)

      {:ok, view, _} = live(conn, "/ingest")
      assert has_element?(view, "#asset-#{asset.id} [data-status=processing]")

      Ingest.simulate_encoding(asset)
      assert render(view) =~ "Pronto"
      assert has_element?(view, "#asset-#{asset.id} [data-status=ready]")
    end
  end

  describe "users (RF14, RF15, runbook 3)" do
    test "editor can't open accounts", %{conn: conn} do
      conn = log_in(conn, staff(:editor))
      assert {:error, {:redirect, %{to: "/ingest"}}} = live(conn, "/usuarios")
    end

    test "support finds the account by watermark code and suspends it", %{conn: conn} do
      user = subscriber_fixture("basico")
      movie = published_movie_fixture()
      {:ok, p} = Bullet.Playback.start_session(user, movie.id, nil)
      conn = log_in(conn, staff(:support))

      {:ok, view, _} = live(conn, "/usuarios")
      view |> form("#user-search") |> render_submit(%{q: p.code})
      assert has_element?(view, "#matched-code")

      {:ok, view, _} = live(conn, "/usuarios/#{user.id}")
      assert has_element?(view, "#sessions", p.code)
      refute has_element?(view, "#grant-form"), "only owner grants plans"

      view |> form("#suspend-form", %{reason: "teste"}) |> render_submit()
      assert has_element?(view, "#account-status", "suspensa")
      assert has_element?(view, "#unsuspend")
    end

    test "owner grants a plan", %{conn: conn} do
      user = user_fixture()
      {:ok, view, _} = live(log_in(conn, staff(:owner)), "/usuarios/#{user.id}")
      view |> form("#grant-form", %{plan: "familia", days: "30"}) |> render_submit()
      assert has_element?(view, "#plan", "Família")
    end
  end
end
