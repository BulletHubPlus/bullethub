defmodule BulletWeb.Api.CatalogController do
  use BulletWeb, :controller

  alias Bullet.{Catalog, Library, Playback}
  alias Bullet.Catalog.{Collection, Genres, Media}
  alias BulletWeb.Api.CatalogJSON

  action_fallback BulletWeb.Api.FallbackController

  def home(conn, _params) do
    user_id = conn.assigns.current_user.id

    rows =
      for {id, title, items} <- Catalog.home_rows() do
        %{id: id, title: title, items: Enum.map(items, &card/1)}
      end

    continue = user_id |> Playback.continue_watching() |> Enum.map(&CatalogJSON.continue_card/1)
    my_list = user_id |> Library.list() |> Enum.map(&card/1)

    json(conn, %{continue_watching: continue, my_list: my_list, rows: rows})
  end

  def search(conn, params) do
    genre = if Genres.valid?(params["genero"]), do: params["genero"]
    query = params["q"] |> to_string() |> String.slice(0, 100)

    json(conn, %{
      query: query,
      genre: genre && %{slug: genre, name: Genres.label(genre)},
      results: query |> Catalog.search_titles(genre) |> Enum.map(&card/1)
    })
  end

  def genres(conn, %{"scope" => "all"}), do: json(conn, %{genres: Catalog.all_genres()})
  def genres(conn, _params), do: json(conn, %{genres: Catalog.genres_in_use()})

  @kinds %{"series" => :series, "animes" => :anime, "filmes" => :movie}

  def browse(conn, %{"kind" => kind}) do
    case Map.fetch(@kinds, kind) do
      {:ok, k} ->
        json(conn, %{kind: kind, results: k |> Catalog.browse_titles() |> Enum.map(&card/1)})

      :error ->
        {:error, :not_found}
    end
  end

  def collection(conn, %{"slug" => slug}) do
    case Catalog.get_published_collection(slug) do
      %Collection{} = c ->
        user_id = conn.assigns.current_user.id
        ids = for s <- c.seasons, m <- s.media, do: m.id
        progress = Playback.progress_map(user_id, ids)

        seasons =
          for s <- c.seasons, s.media != [] do
            media = Enum.map(s.media, &Map.put(media(&1), :progress, progress[&1.id]))
            %{id: s.id, number: s.number, title: s.title, media: media}
          end

        collection =
          c
          |> card()
          |> Map.merge(details(c))
          |> Map.put(:in_my_list, Library.member?(user_id, :collection, c.id))

        json(conn, %{collection: collection, seasons: seasons})

      nil ->
        {:error, :not_found}
    end
  end

  def movie(conn, %{"id" => id}) do
    case Catalog.get_published_movie(id) do
      %Media{} = m ->
        user_id = conn.assigns.current_user.id

        body =
          m
          |> media()
          |> Map.merge(card(m))
          |> Map.merge(details(m))
          |> Map.merge(%{
            progress: Playback.progress_map(user_id, [m.id])[m.id],
            in_my_list: Library.member?(user_id, :movie, m.id)
          })

        json(conn, %{media: body})

      nil ->
        {:error, :not_found}
    end
  end

  # Title card: everything a row, the search grid or the hero needs.
  defp card(%Collection{} = c) do
    Map.merge(
      %{
        type: "collection",
        id: c.id,
        kind: c.kind,
        slug: c.slug,
        title: c.title,
        description: c.description,
        thumbnail_url: Catalog.thumbnail_for_collection(c)
      },
      metadata(c)
    )
  end

  defp card(%Media{} = m) do
    Map.merge(
      %{
        type: "movie",
        id: m.id,
        kind: m.kind,
        title: m.title,
        description: m.synopsis,
        thumbnail_url: Catalog.thumbnail_for(m),
        duration_seconds: m.asset.duration_seconds
      },
      metadata(m)
    )
  end

  defp metadata(title) do
    %{
      original_title: title.original_title,
      release_year: title.release_year,
      age_rating: title.age_rating,
      genres: Enum.map(title.genres, &%{slug: &1, name: Genres.label(&1)}),
      poster_url: title.poster_url,
      backdrop_url: title.backdrop_url
    }
  end

  # Detail page only.
  defp details(title), do: %{cast: title.cast, creators: title.creators}

  defp media(%Media{} = m) do
    %{
      id: m.id,
      kind: m.kind,
      position: m.position,
      title: m.title,
      synopsis: m.synopsis,
      thumbnail_url: Catalog.thumbnail_for(m),
      duration_seconds: m.asset.duration_seconds,
      intro_end_seconds: m.intro_end_seconds
    }
  end
end
