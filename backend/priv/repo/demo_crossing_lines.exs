# Demo catalog entry: the series "Crossing Lines" (dev only). Idempotent - skips
# if the slug already exists. Uses the Fake media provider (episodes play the
# local /dev/sample.mp4), so it needs no Bunny account. Cover art is served
# locally from priv/static/images/crossing-lines/.
#
#     cd backend && mix run priv/repo/demo_crossing_lines.exs
#
# Episode titles are generic placeholders ("Episódio N"); rename them in the
# admin panel. Season sizes: S1 = 10, S2 = 12, S3 = 12.

import Ecto.Query
alias Bullet.{Catalog, Ingest, Repo}

slug = "crossing-lines"

if Repo.exists?(from c in Catalog.Collection, where: c.slug == ^slug) do
  IO.puts("crossing-lines já existe - nada a fazer")
else
  {:ok, series} =
    Catalog.create_collection(%{
      kind: :series,
      title: "Crossing Lines",
      slug: slug,
      release_year: 2013,
      age_rating: "14",
      genres: ["crime", "drama", "suspense"],
      description:
        "Uma equipe policial internacional persegue criminosos que cruzam " <>
          "fronteiras na Europa, onde nenhuma polícia nacional tem alcance sozinha.",
      thumbnail_url: "/images/crossing-lines/backdrop.webp",
      poster_url: "/images/crossing-lines/poster.webp",
      backdrop_url: "/images/crossing-lines/backdrop.webp"
    })

  publish_episode = fn media ->
    {:ok, asset, _creds} = Ingest.start_upload(media)
    {:ok, asset} = Ingest.mark_uploaded(asset)
    {:ok, _asset} = Ingest.simulate_encoding(asset)
    {:ok, _media} = Catalog.publish_media(media)
  end

  for {number, episodes} <- [{1, 10}, {2, 12}, {3, 12}] do
    {:ok, season} = Catalog.create_season(series, %{number: number, title: "Temporada #{number}"})

    for position <- 1..episodes do
      {:ok, episode} =
        Catalog.create_item(season, %{
          title: "Episódio #{position}",
          position: position,
          synopsis: "Temporada #{number}, episódio #{position}.",
          intro_end_seconds: 8
        })

      publish_episode.(episode)
    end

    IO.puts("temporada #{number}: #{episodes} episódios publicados")
  end

  {:ok, _} = Catalog.set_collection_published(series, true)
  IO.puts("Crossing Lines publicada em /titulo/#{slug}")
end
