defmodule Bullet.CatalogDiscoveryTest do
  use Bullet.DataCase, async: true

  import Bullet.AccountsFixtures
  import Bullet.CatalogFixtures

  alias Bullet.{Catalog, Library}
  alias Bullet.Catalog.Caption

  defp playable_series(attrs) do
    c = collection_fixture(attrs)
    ep = c |> season_fixture() |> item_fixture()
    with_asset(ep, :ready)
    {:ok, _} = Catalog.publish_media(ep)
    {:ok, c} = Catalog.set_collection_published(c, true)
    c
  end

  describe "metadata" do
    test "cast/creators accept comma-separated text; year, rating and genres are validated" do
      {:ok, c} =
        Catalog.create_collection(%{
          "kind" => "anime",
          "title" => "Lâmina",
          "cast" => "Ana, Bruno ,, Carla",
          "creators" => "Estúdio X",
          "genres" => ["", "acao", "shounen"],
          "age_rating" => "14",
          "release_year" => "2024"
        })

      assert c.cast == ["Ana", "Bruno", "Carla"]
      assert c.creators == ["Estúdio X"]
      assert c.genres == ["acao", "shounen"]

      {:error, cs} =
        Catalog.create_collection(%{
          kind: :series,
          title: "X",
          age_rating: "13",
          genres: ["nope"],
          release_year: 1700
        })

      errors = errors_on(cs)
      assert errors.age_rating != [] and errors.genres != [] and errors.release_year != []
    end

    test "episodes ignore title metadata; movies take it" do
      season = collection_fixture() |> season_fixture()
      {:ok, ep} = Catalog.create_item(season, %{title: "E1", position: 1, genres: ["acao"]})
      assert ep.genres == []

      {:ok, m} = Catalog.create_movie(%{title: "Filme", genres: ["drama"], age_rating: "L"})
      assert m.genres == ["drama"] and m.age_rating == "L"
    end
  end

  describe "search_titles/2" do
    setup do
      published_movie_fixture(title: "Ação no Porto", genres: ["acao"], cast: ["Joana Prado"])

      published_movie_fixture(
        title: "Maré Alta",
        synopsis: "Uma ação silenciosa",
        genres: ["drama"]
      )

      playable_series(
        title: "Noite Neon",
        original_title: "Neon Night",
        genres: ["crime", "drama"]
      )

      :ok
    end

    test "accent/case-insensitive; title matches rank before synopsis matches" do
      assert ["Ação no Porto", "Maré Alta"] ==
               "ACAO" |> Catalog.search_titles() |> Enum.map(& &1.title)
    end

    test "matches original title and cast" do
      assert [%{title: "Noite Neon"}] = Catalog.search_titles("neon night")
      assert [%{title: "Ação no Porto"}] = Catalog.search_titles("joana")
    end

    test "genre filter, alone or combined" do
      assert ["Maré Alta", "Noite Neon"] |> Enum.sort() ==
               "" |> Catalog.search_titles("drama") |> Enum.map(& &1.title) |> Enum.sort()

      assert [%{title: "Noite Neon"}] = Catalog.search_titles("noite", "drama")
      assert [] = Catalog.search_titles("noite", "acao")
    end

    test "genres_in_use counts playable titles only" do
      movie_fixture(title: "Rascunho", genres: ["terror"])
      in_use = Map.new(Catalog.genres_in_use(), &{&1.slug, &1.count})
      assert in_use == %{"acao" => 1, "drama" => 2, "crime" => 1}
    end

    test "home adds genre rows, biggest first" do
      ids = Catalog.home_rows() |> Enum.map(&elem(&1, 0))
      assert "genero-drama" in ids

      assert Enum.find_index(ids, &(&1 == "genero-drama")) <
               Enum.find_index(ids, &(&1 == "genero-acao"))
    end
  end

  describe "Minha lista" do
    test "add is idempotent, list keeps newest first and hides unplayable titles" do
      user = user_fixture()
      movie = published_movie_fixture(title: "Filme A")
      series = playable_series(title: "Série B")

      :ok = Library.add(user.id, :movie, movie.id)
      :ok = Library.add(user.id, :movie, movie.id)
      :ok = Library.add(user.id, :collection, series.id)
      assert ["Série B", "Filme A"] == user.id |> Library.list() |> Enum.map(& &1.title)
      assert Library.member?(user.id, :movie, movie.id)

      {:ok, _} = Catalog.unpublish_media(movie)
      assert ["Série B"] == user.id |> Library.list() |> Enum.map(& &1.title)

      :ok = Library.remove(user.id, :collection, series.id)
      refute Library.member?(user.id, :collection, series.id)
      assert {:error, :not_found} = Library.add(user.id, :movie, movie_fixture().id)
      assert {:error, :not_found} = Library.add(user.id, :movie, "nope")
    end
  end

  describe "captions" do
    test "SRT becomes WebVTT; garbage is rejected" do
      srt = "﻿1\r\n00:00:01,500 --> 00:00:03,000\r\nOlá\r\n"
      assert {:ok, "WEBVTT\n\n1\n00:00:01.500 --> 00:00:03.000\nOlá\n"} = Caption.to_vtt(srt)
      assert {:ok, "WEBVTT\n\nx\n"} = Caption.to_vtt("WEBVTT\n\nx")
      assert {:error, :invalid} = Caption.to_vtt("não é legenda")
    end

    test "put_caption needs a video, upserts per language and shows in the playback payload" do
      movie = movie_fixture()
      assert {:error, :no_video} = Catalog.put_caption(movie, "pt-BR", "WEBVTT\n\nx")

      with_asset(movie, :ready)
      {:ok, movie} = Catalog.publish_media(movie)
      assert {:ok, first} = Catalog.put_caption(movie, "pt-BR", "WEBVTT\n\nv1")
      assert {:ok, _} = Catalog.put_caption(movie, "pt-BR", "WEBVTT\n\nv2")

      assert [%{id: id, label: "Português", content: "WEBVTT\n\nv2\n"}] =
               Catalog.list_captions(movie)

      assert id == first.id

      {:ok, p} = Bullet.Playback.start_session(subscriber_fixture(), movie.id, nil)
      assert [%{srclang: "pt-BR", label: "Português"}] = p.captions
    end
  end
end
