defmodule Bullet.CatalogTest do
  use Bullet.DataCase, async: true

  import Bullet.CatalogFixtures

  alias Bullet.Catalog
  alias Bullet.Catalog.Media

  test "same form builds a 2-season series and a 3-season anime (Fase 1 exit, RF09)" do
    series = collection_fixture(kind: :series, title: "Minha Série")
    anime = collection_fixture(kind: :anime, title: "Lâmina Carmesim")

    for n <- 1..2, do: series |> season_fixture(n) |> item_fixture()
    for n <- 1..3, do: anime |> season_fixture(n) |> item_fixture()

    series = Catalog.get_collection!(series.id)
    anime = Catalog.get_collection!(anime.id)

    assert length(series.seasons) == 2
    assert length(anime.seasons) == 3
    assert Enum.all?(series.seasons, fn s -> Enum.all?(s.media, &(&1.kind == :episode)) end)
    assert Enum.all?(anime.seasons, fn s -> Enum.all?(s.media, &(&1.kind == :episode)) end)
    assert series.slug == "minha-serie"
  end

  test "slugify strips accents and punctuation" do
    assert Catalog.Collection.slugify("Ação & Reação: Temporada 2!") == "acao-reacao-temporada-2"
  end

  test "positions are unique per season" do
    season = collection_fixture() |> season_fixture()
    item_fixture(season, position: 1)
    assert {:error, cs} = Catalog.create_item(season, %{title: "Dup", position: 1})
    assert "já existe nesta temporada" in errors_on(cs).season_id
  end

  test "DB rejects a movie inside a collection" do
    c = collection_fixture()

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(%Media{
        kind: :movie,
        title: "x",
        collection_id: c.id,
        season_id: c |> season_fixture() |> Map.get(:id)
      })
    end
  end

  describe "publish_media/1" do
    test "requires a ready asset" do
      m = movie_fixture()
      assert {:error, :asset_not_ready} = Catalog.publish_media(m)

      with_asset(m, :processing)
      assert {:error, :asset_not_ready} = Catalog.publish_media(m)

      Bullet.Ingest.simulate_encoding(Repo.preload(m, :asset).asset)
      assert {:ok, %{published_at: %DateTime{}}} = Catalog.publish_media(m)
    end
  end

  describe "home_rows/0" do
    test "only published + ready content; collections need a playable item" do
      published = published_movie_fixture(title: "Visível")
      _draft = movie_fixture(title: "Rascunho")

      empty_series = collection_fixture(title: "Vazia")
      Catalog.set_collection_published(empty_series, true)

      series = collection_fixture(title: "Com Episódio")
      ep = series |> season_fixture() |> item_fixture()
      with_asset(ep, :ready)
      {:ok, _} = Catalog.publish_media(ep)
      Catalog.set_collection_published(series, true)

      rows =
        Map.new(Catalog.home_rows(), fn {id, _, items} -> {id, Enum.map(items, & &1.title)} end)

      assert rows["filmes"] == ["Visível"]
      assert rows["series"] == ["Com Episódio"]
      refute Map.has_key?(rows, "animes")
      assert "Visível" in rows["novidades"] and "Com Episódio" in rows["novidades"]
      refute Enum.any?(Map.values(rows), &("Vazia" in &1 or "Rascunho" in &1))
      assert published.id
    end
  end
end
