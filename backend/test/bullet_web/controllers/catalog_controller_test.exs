defmodule BulletWeb.Api.CatalogControllerTest do
  use BulletWeb.ConnCase, async: true

  import Bullet.AccountsFixtures
  import Bullet.CatalogFixtures

  alias Bullet.Catalog

  setup %{conn: conn} do
    %{user: user, device: device} = session_fixture()
    token = BulletWeb.AccessToken.sign(user.id, device.id)
    %{conn: put_req_header(conn, "authorization", "Bearer " <> token)}
  end

  test "home requires auth" do
    assert json_response(get(build_conn(), ~p"/api/catalog/home"), 401)
  end

  test "home lists playable content with thumbnails", %{conn: conn} do
    movie = published_movie_fixture(title: "Filme Pronto")

    assert %{"rows" => rows, "continue_watching" => []} =
             conn |> get(~p"/api/catalog/home") |> json_response(200)

    filmes = Enum.find(rows, &(&1["id"] == "filmes"))

    assert [
             %{
               "type" => "movie",
               "id" => id,
               "thumbnail_url" => "https://vz-test.b-cdn.net/" <> _
             }
           ] = filmes["items"]

    assert id == movie.id
  end

  test "collection by slug hides unpublished items and empty seasons", %{conn: conn} do
    c = collection_fixture(title: "Anime X", kind: :anime)
    s1 = season_fixture(c, 1)
    s2 = season_fixture(c, 2)
    ok = item_fixture(s1, title: "Ep 1")
    with_asset(ok, :ready)
    {:ok, _} = Catalog.publish_media(ok)
    item_fixture(s1, title: "Rascunho")
    item_fixture(s2, title: "Outra")

    assert json_response(get(conn, ~p"/api/catalog/collections/anime-x"), 404)

    Catalog.set_collection_published(c, true)
    body = conn |> get(~p"/api/catalog/collections/anime-x") |> json_response(200)
    assert body["collection"]["kind"] == "anime"

    assert [%{"number" => 1, "media" => [%{"title" => "Ep 1", "kind" => "episode"}]}] =
             body["seasons"]
  end

  test "movie by id; unknown or malformed → 404", %{conn: conn} do
    m = published_movie_fixture()

    assert %{"media" => %{"id" => _}} =
             conn |> get(~p"/api/catalog/movies/#{m.id}") |> json_response(200)

    assert json_response(get(conn, ~p"/api/catalog/movies/#{UUIDv7.generate()}"), 404)
    assert json_response(get(conn, ~p"/api/catalog/movies/nope"), 404)
  end
end
