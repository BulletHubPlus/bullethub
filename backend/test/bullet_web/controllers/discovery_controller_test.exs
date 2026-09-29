defmodule BulletWeb.Api.DiscoveryControllerTest do
  use BulletWeb.ConnCase, async: true

  import Bullet.AccountsFixtures
  import Bullet.CatalogFixtures

  setup %{conn: conn} do
    user = subscriber_fixture()
    {:ok, %{device: d}} = Bullet.Accounts.login(user.email, valid_password(), %{})

    %{
      conn:
        put_req_header(
          conn,
          "authorization",
          "Bearer " <> BulletWeb.AccessToken.sign(user.id, d.id)
        )
    }
  end

  test "search returns cards with metadata; unknown genre is ignored", %{conn: conn} do
    published_movie_fixture(
      title: "Ação no Porto",
      genres: ["acao"],
      release_year: 2023,
      age_rating: "14"
    )

    body = conn |> get(~p"/api/catalog/search?q=acao&genero=acao") |> json_response(200)
    assert %{"genre" => %{"name" => "Ação"}, "results" => [card]} = body

    assert %{
             "title" => "Ação no Porto",
             "release_year" => 2023,
             "age_rating" => "14",
             "genres" => [%{"slug" => "acao", "name" => "Ação"}]
           } = card

    assert %{"genre" => nil} =
             conn |> get(~p"/api/catalog/search?q=x&genero=invalido") |> json_response(200)

    assert %{"genres" => [%{"slug" => "acao", "count" => 1}]} =
             conn |> get(~p"/api/catalog/genres") |> json_response(200)
  end

  test "Minha lista round trip through home and the title page", %{conn: conn} do
    movie = published_movie_fixture(title: "Para depois", cast: ["Fulano"])

    assert response(put(conn, ~p"/api/me/list/movie/#{movie.id}"), 204)

    assert %{"my_list" => [%{"id" => id}]} =
             conn |> get(~p"/api/catalog/home") |> json_response(200)

    assert id == movie.id

    assert %{"media" => %{"in_my_list" => true, "cast" => ["Fulano"]}} =
             conn |> get(~p"/api/catalog/movies/#{movie.id}") |> json_response(200)

    assert response(delete(conn, ~p"/api/me/list/movie/#{movie.id}"), 204)
    assert %{"my_list" => []} = conn |> get(~p"/api/catalog/home") |> json_response(200)
    assert json_response(put(conn, ~p"/api/me/list/bogus/#{movie.id}"), 404)
  end

  test "browse by kind lists only that kind; unknown kind → 404", %{conn: conn} do
    series = collection_fixture(kind: :series, title: "Uma Série")
    ep = series |> season_fixture() |> item_fixture()
    with_asset(ep, :ready)
    {:ok, _} = Bullet.Catalog.publish_media(ep)
    {:ok, _} = Bullet.Catalog.set_collection_published(series, true)
    published_movie_fixture(title: "Um Filme")

    body = conn |> get(~p"/api/catalog/browse/series") |> json_response(200)
    assert body["kind"] == "series"

    assert [%{"type" => "collection", "kind" => "series", "title" => "Uma Série"}] =
             body["results"]

    filmes = (conn |> get(~p"/api/catalog/browse/filmes") |> json_response(200))["results"]
    assert Enum.all?(filmes, &(&1["kind"] == "movie"))

    assert json_response(get(conn, ~p"/api/catalog/browse/bogus"), 404)
  end

  test "caption file is served as text/vtt", %{conn: conn} do
    movie = published_movie_fixture()
    {:ok, cap} = Bullet.Catalog.put_caption(movie, "en", "1\n00:00:01,000 --> 00:00:02,000\nHi\n")

    conn = get(conn, ~p"/api/captions/#{cap.id}")
    assert response(conn, 200) =~ "00:00:01.000 --> 00:00:02.000"
    assert [ct] = get_resp_header(conn, "content-type")
    assert ct =~ "text/vtt"
  end
end
