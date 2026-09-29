defmodule BulletWeb.Api.PlaybackControllerTest do
  use BulletWeb.ConnCase, async: true

  import Bullet.AccountsFixtures
  import Bullet.CatalogFixtures

  alias Bullet.Accounts.User
  alias Bullet.Catalog

  defp authed(conn, user) do
    {:ok, %{device: d}} = Bullet.Accounts.login(user.email, valid_password(), %{})
    put_req_header(conn, "authorization", "Bearer " <> BulletWeb.AccessToken.sign(user.id, d.id))
  end

  test "201 with source, watermark and next episode", %{conn: conn} do
    c = collection_fixture()
    s = season_fixture(c)

    [e1, e2] =
      for t <- ["E1", "E2"] do
        m = item_fixture(s, title: t)
        with_asset(m, :ready)
        {:ok, m} = Catalog.publish_media(m)
        m
      end

    body =
      conn
      |> authed(subscriber_fixture())
      |> post(~p"/api/playback/sessions", %{media_id: e1.id})
      |> json_response(201)

    assert %{
             "session_id" => _,
             "code" => code,
             "source" => %{"engine" => "native"},
             "resume_position" => 0
           } = body

    assert body["watermark"]["text"] =~ code
    assert body["media"]["collection"]["slug"] == c.slug
    assert body["next_media"]["id"] == e2.id
  end

  test "402 without plan, 403 unconfirmed, 409 with active sessions", %{conn: conn} do
    movie = published_movie_fixture()

    unconfirmed = user_fixture()
    Bullet.Billing.grant(unconfirmed, "padrao")

    assert %{"error" => %{"code" => "email_unconfirmed"}} =
             conn
             |> authed(unconfirmed)
             |> post(~p"/api/playback/sessions", %{media_id: movie.id})
             |> json_response(403)

    no_plan = Bullet.Repo.update!(User.confirm_changeset(user_fixture()))

    assert %{"error" => %{"code" => "subscription_required"}} =
             build_conn()
             |> authed(no_plan)
             |> post(~p"/api/playback/sessions", %{media_id: movie.id})
             |> json_response(402)

    user = subscriber_fixture("basico")
    authed = build_conn() |> authed(user)
    assert json_response(post(authed, ~p"/api/playback/sessions", %{media_id: movie.id}), 201)

    assert %{
             "error" => %{
               "code" => "stream_limit",
               "details" => %{"active_sessions" => [%{"id" => id}]}
             }
           } =
             authed
             |> post(~p"/api/playback/sessions", %{media_id: movie.id})
             |> json_response(409)

    assert response(delete(authed, ~p"/api/playback/sessions/#{id}"), 204)
    assert json_response(post(authed, ~p"/api/playback/sessions", %{media_id: movie.id}), 201)
  end

  test "progress fallback, continue watching and per-episode progress", %{conn: conn} do
    user = subscriber_fixture()
    movie = published_movie_fixture(title: "Pela metade")
    authed = authed(conn, user)

    assert response(put(authed, ~p"/api/progress/#{movie.id}", %{position: 75}), 204)
    assert json_response(put(authed, ~p"/api/progress/#{UUIDv7.generate()}", %{position: 1}), 404)

    home = authed |> get(~p"/api/catalog/home") |> json_response(200)

    assert [
             %{
               "type" => "progress",
               "title" => "Pela metade",
               "position" => 75,
               "duration_seconds" => 150
             }
           ] = home["continue_watching"]

    assert %{"media" => %{"progress" => %{"position" => 75, "completed" => false}}} =
             authed |> get(~p"/api/catalog/movies/#{movie.id}") |> json_response(200)
  end

  test "telemetry accepts a QoE batch and emits :telemetry", %{conn: conn} do
    ref = :telemetry_test.attach_event_handlers(self(), [[:bullet, :playback, :ttff]])
    authed = authed(conn, subscriber_fixture())

    assert response(
             post(authed, ~p"/api/telemetry", %{
               events: [%{kind: "ttff", ms: 850, engine: "bunny"}, %{kind: "bogus", ms: 1}]
             }),
             202
           )

    assert_receive {[:bullet, :playback, :ttff], ^ref, %{duration_ms: 850}, %{engine: "bunny"}}
  end

  test "/api/me exposes the subscription", %{conn: conn} do
    body = conn |> authed(subscriber_fixture("familia")) |> get(~p"/api/me") |> json_response(200)

    assert %{
             "subscription" => %{
               "status" => "active",
               "plan" => %{"slug" => "familia", "max_streams" => 4}
             }
           } = body
  end
end
