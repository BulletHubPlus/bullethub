defmodule Bullet.Catalog do
  @moduledoc """
  Catalog context (RF09): generic `Collection → Season → Media` hierarchy that
  models series and anime (both collection → season →
  episode). A movie is a `Media` with no collection.

  Public reads (`home_rows/0`, `get_published_*`) only ever return media that is
  published **and** whose asset is `ready`.
  """

  import Ecto.Query

  alias Bullet.Catalog.{Caption, Collection, Genres, Media, Season}
  alias Bullet.Ingest
  alias Bullet.Ingest.MediaAsset
  alias Bullet.Media.Provider
  alias Bullet.Repo

  ## Collections (admin)

  def list_collections do
    Repo.all(
      from c in Collection,
        left_join: m in assoc(c, :media),
        group_by: c.id,
        order_by: [desc: c.inserted_at],
        select: %{collection: c, media_count: count(m.id)}
    )
  end

  def get_collection!(id) do
    Collection
    |> Repo.get!(id)
    |> Repo.preload(seasons: [media: :asset])
  end

  def change_collection(%Collection{} = c, attrs \\ %{}), do: Collection.changeset(c, attrs)

  def create_collection(attrs), do: %Collection{} |> Collection.changeset(attrs) |> Repo.insert()

  def update_collection(%Collection{} = c, attrs),
    do: c |> Collection.changeset(attrs) |> Repo.update()

  def delete_collection(%Collection{} = c) do
    c = Repo.preload(c, media: :asset)
    Enum.each(c.media, &Ingest.discard_remote_asset(&1.asset))
    Repo.delete(c)
  end

  def set_collection_published(%Collection{} = c, published?) do
    c
    |> Ecto.Changeset.change(published_at: if(published?, do: DateTime.utc_now()))
    |> Repo.update()
  end

  ## Seasons (admin)

  def change_season(%Season{} = s, attrs \\ %{}), do: Season.changeset(s, attrs)

  def create_season(%Collection{id: id}, attrs) do
    %Season{collection_id: id} |> Season.changeset(attrs) |> Repo.insert()
  end

  def next_season_number(%Collection{id: id}) do
    (Repo.one(from s in Season, where: s.collection_id == ^id, select: max(s.number)) || 0) + 1
  end

  def delete_season(%Season{} = s) do
    s = Repo.preload(s, media: :asset)
    Enum.each(s.media, &Ingest.discard_remote_asset(&1.asset))
    Repo.delete(s)
  end

  ## Media (admin)

  def list_movies do
    Repo.all(
      from m in Media, where: m.kind == :movie, order_by: [desc: m.inserted_at], preload: :asset
    )
  end

  def get_media!(id), do: Media |> Repo.get!(id) |> Repo.preload([:asset, :collection, :season])

  def change_media(%Media{} = m, attrs \\ %{}), do: Media.changeset(m, attrs)

  def create_movie(attrs), do: %Media{kind: :movie} |> Media.changeset(attrs) |> Repo.insert()

  def create_item(%Season{} = season, attrs) do
    season = Repo.preload(season, :collection)

    %Media{kind: :episode, collection_id: season.collection_id, season_id: season.id}
    |> Media.changeset(attrs)
    |> Repo.insert()
  end

  def next_position(%Season{id: id}) do
    (Repo.one(from m in Media, where: m.season_id == ^id, select: max(m.position)) || 0) + 1
  end

  def update_media(%Media{} = m, attrs), do: m |> Media.changeset(attrs) |> Repo.update()

  def delete_media(%Media{} = m) do
    m = Repo.preload(m, :asset)
    Ingest.discard_remote_asset(m.asset)
    Repo.delete(m)
  end

  @doc "`published_at` can only be set when the asset is `ready` (PRD §9)."
  @spec publish_media(Media.t()) :: {:ok, Media.t()} | {:error, :asset_not_ready}
  def publish_media(%Media{} = m) do
    case Repo.preload(m, :asset, force: true).asset do
      %MediaAsset{status: :ready} ->
        m |> Ecto.Changeset.change(published_at: DateTime.utc_now()) |> Repo.update()

      _ ->
        {:error, :asset_not_ready}
    end
  end

  def unpublish_media(%Media{} = m),
    do: m |> Ecto.Changeset.change(published_at: nil) |> Repo.update()

  ## Public reads (SPA)

  # Published media whose asset is ready. `playable_filter` is usable in subqueries
  # (no preload); `playable_query` also preloads the asset.
  defp playable_filter do
    from m in Media,
      as: :media,
      join: a in assoc(m, :asset),
      as: :asset,
      where: not is_nil(m.published_at) and a.status == :ready
  end

  defp playable_query, do: from([media: m, asset: a] in playable_filter(), preload: [asset: a])

  @max_titles 500

  @doc """
  Every playable title: published collections with at least one playable item,
  plus playable movies, newest first. The catalog is small (hundreds of
  titles), so rows, genres and search work on this list in memory.
  """
  def playable_titles(limit \\ @max_titles) do
    movies =
      Repo.all(
        from m in playable_query(),
          where: m.kind == :movie,
          order_by: [desc: m.published_at],
          limit: ^limit
      )

    (movies ++ published_collections(limit))
    |> Enum.sort_by(& &1.published_at, {:desc, DateTime})
  end

  @doc "Rows for the SPA home: newest, by kind, then the most populated genres. Empty rows are dropped."
  def home_rows(per_row \\ 20, genre_rows \\ 6) do
    titles = playable_titles()
    by_kind = fn kind -> Enum.filter(titles, &(title_kind(&1) == kind)) end

    base = [
      {"novidades", "Novidades", titles},
      {"series", "Séries", by_kind.(:series)},
      {"animes", "Animes", by_kind.(:anime)},
      {"filmes", "Filmes", by_kind.(:movie)}
    ]

    genres =
      titles
      |> Enum.flat_map(fn t -> Enum.map(t.genres, &{&1, t}) end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.sort_by(fn {_slug, items} -> -length(items) end)
      |> Enum.take(genre_rows)
      |> Enum.map(fn {slug, items} -> {"genero-" <> slug, Genres.label(slug), items} end)

    (base ++ genres)
    |> Enum.map(fn {id, title, items} -> {id, title, Enum.take(items, per_row)} end)
    |> Enum.reject(fn {_, _, items} -> items == [] end)
  end

  @doc "All playable titles of one kind (:series, :anime, :movie), newest first."
  def browse_titles(kind) when kind in [:series, :anime, :movie] do
    Enum.filter(playable_titles(), &(title_kind(&1) == kind))
  end

  defp title_kind(%Media{}), do: :movie
  defp title_kind(%Collection{kind: kind}), do: kind

  @doc """
  Search over playable titles: accent- and case-insensitive match on title,
  original title, synopsis, cast and creators; optional genre filter. Title
  matches rank first.
  """
  def search_titles(query, genre \\ nil) do
    needle = normalize(query || "")

    playable_titles()
    |> Enum.filter(&(is_nil(genre) or genre in &1.genres))
    |> Enum.flat_map(fn title ->
      cond do
        needle == "" ->
          [{2, title}]

        String.contains?(normalize(title.title <> " " <> (title.original_title || "")), needle) ->
          [{0, title}]

        String.contains?(normalize(searchable_text(title)), needle) ->
          [{1, title}]

        true ->
          []
      end
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  defp searchable_text(%Collection{} = c),
    do: Enum.join([c.description || "" | c.cast ++ c.creators], " ")

  defp searchable_text(%Media{} = m),
    do: Enum.join([m.synopsis || "" | m.cast ++ m.creators], " ")

  @doc ~S|Lowercase, no accents: "Ação" and "acao" match.|
  def normalize(text) do
    text
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
    |> String.downcase()
    |> String.trim()
  end

  @doc "Every defined genre (slug + label), for navigation menus."
  def all_genres, do: Enum.map(Genres.all(), fn {slug, name} -> %{slug: slug, name: name} end)

  @doc "Genres that have at least one playable title, with counts."
  def genres_in_use do
    counts = playable_titles() |> Enum.flat_map(& &1.genres) |> Enum.frequencies()
    for {slug, label} <- Genres.all(), n = counts[slug], do: %{slug: slug, name: label, count: n}
  end

  # A published collection only shows up once it has at least one playable item.
  defp published_collections(limit) do
    playable = playable_query()

    Repo.all(
      from c in Collection,
        where: not is_nil(c.published_at),
        where: c.id in subquery(from m in playable_filter(), select: m.collection_id),
        order_by: [desc: c.published_at],
        limit: ^limit,
        preload: [media: ^from(m in playable, order_by: [asc: m.season_id, asc: m.position])]
    )
  end

  def get_published_collection(slug) do
    playable = from m in playable_query(), order_by: [asc: m.position]

    Repo.one(
      from c in Collection,
        where: c.slug == ^slug and not is_nil(c.published_at),
        preload: [seasons: [media: ^playable]]
    )
  end

  def get_published_movie(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        Repo.one(from m in playable_query(), where: m.id == ^uuid and m.kind == :movie)

      :error ->
        nil
    end
  end

  ## Captions

  def list_captions(%Media{id: id}),
    do: Repo.all(from c in Caption, where: c.media_id == ^id, order_by: c.srclang)

  def get_caption(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Caption, uuid)
      :error -> nil
    end
  end

  @doc """
  Adds or replaces the track for a language: converted to WebVTT, stored, and
  pushed to the provider (needs the video to exist there).
  """
  @spec put_caption(Media.t(), String.t(), binary()) ::
          {:ok, Caption.t()} | {:error, :no_video | :invalid_file | Ecto.Changeset.t() | term()}
  def put_caption(%Media{} = media, srclang, raw) do
    media = Repo.preload(media, :asset, force: true)
    label = Caption.languages() |> Map.new() |> Map.get(srclang)

    with %MediaAsset{bunny_video_id: video_id} <- media.asset || {:error, :no_video},
         {:ok, vtt} <- Caption.to_vtt(raw) |> invalid_as(:invalid_file),
         %Ecto.Changeset{valid?: true} = cs <-
           Caption.changeset(%Caption{media_id: media.id}, %{
             srclang: srclang,
             label: label,
             content: vtt
           }),
         :ok <- Provider.upload_caption(video_id, srclang, label || srclang, vtt) do
      Repo.insert(cs,
        on_conflict: {:replace, [:label, :content, :updated_at]},
        conflict_target: [:media_id, :srclang]
      )
    else
      %Ecto.Changeset{} = cs -> {:error, cs}
      error -> error
    end
  end

  def delete_caption(%Caption{} = caption) do
    %{asset: asset} = Repo.preload(caption, media: :asset).media
    if asset, do: Provider.delete_caption(asset.bunny_video_id, caption.srclang)
    Repo.delete(caption)
  end

  defp invalid_as({:error, :invalid}, reason), do: {:error, reason}
  defp invalid_as(ok, _), do: ok

  @doc "Any playable media (movie or episode) with its collection and season."
  def get_playable_media(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        Repo.one(
          from m in playable_query(), where: m.id == ^uuid, preload: [:collection, :season]
        )

      :error ->
        nil
    end
  end

  @doc """
  What autoplay should queue after `media` (RF04): the next position in the
  same season, else the first item of the next season. Movies have none.
  """
  def next_media(%Media{season_id: nil}), do: nil

  def next_media(%Media{} = media) do
    media = Repo.preload(media, :season)

    Repo.one(
      from m in playable_query(),
        join: s in assoc(m, :season),
        where: m.collection_id == ^media.collection_id,
        where:
          (s.number == ^media.season.number and m.position > ^media.position) or
            s.number > ^media.season.number,
        order_by: [asc: s.number, asc: m.position],
        limit: 1
    )
  end

  @doc "Admin-provided thumbnail, else the one Bunny generated for the video."
  def thumbnail_for(%Media{thumbnail_url: url}) when is_binary(url), do: url
  def thumbnail_for(%Media{asset: %MediaAsset{} = asset}), do: Ingest.thumbnail_url(asset)
  def thumbnail_for(_), do: nil

  def thumbnail_for_collection(%Collection{thumbnail_url: url}) when is_binary(url), do: url

  def thumbnail_for_collection(%Collection{media: [first | _]}), do: thumbnail_for(first)

  def thumbnail_for_collection(%Collection{seasons: seasons}) when is_list(seasons) do
    seasons |> Enum.flat_map(& &1.media) |> List.first() |> thumbnail_for()
  end

  def thumbnail_for_collection(_), do: nil
end
