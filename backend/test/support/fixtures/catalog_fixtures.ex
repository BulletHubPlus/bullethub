defmodule Bullet.CatalogFixtures do
  @moduledoc false
  alias Bullet.{Catalog, Ingest}

  def collection_fixture(attrs \\ %{}) do
    {:ok, c} =
      attrs
      |> Enum.into(%{kind: :series, title: "Série #{System.unique_integer([:positive])}"})
      |> Catalog.create_collection()

    c
  end

  def season_fixture(collection, number \\ 1) do
    {:ok, s} = Catalog.create_season(collection, %{number: number})
    s
  end

  def item_fixture(season, attrs \\ %{}) do
    {:ok, m} =
      Catalog.create_item(
        season,
        Enum.into(attrs, %{title: "Item", position: Catalog.next_position(season)})
      )

    m
  end

  def movie_fixture(attrs \\ %{}) do
    {:ok, m} =
      Catalog.create_movie(
        Enum.into(attrs, %{title: "Filme #{System.unique_integer([:positive])}"})
      )

    m
  end

  @doc "Media with an asset in the given status (Fake provider)."
  def with_asset(media, status) do
    {:ok, asset, _} = Ingest.start_upload(media)

    case status do
      :uploading ->
        asset

      :processing ->
        elem(Ingest.mark_uploaded(asset), 1)

      :ready ->
        asset |> Ingest.mark_uploaded() |> elem(1) |> Ingest.simulate_encoding() |> elem(1)

      :failed ->
        asset
        |> Ingest.mark_uploaded()
        |> elem(1)
        |> Ingest.advance(:failed, %{error: "x"})
        |> elem(1)
    end
  end

  def published_movie_fixture(attrs \\ %{}) do
    m = movie_fixture(attrs)
    with_asset(m, :ready)
    {:ok, m} = Catalog.publish_media(m)
    m
  end

  def sign_bunny(body),
    do: :crypto.mac(:hmac, :sha256, "test-readonly-key", body) |> Base.encode16(case: :lower)
end
