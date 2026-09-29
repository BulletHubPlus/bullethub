defmodule BulletWeb.Api.CatalogJSON do
  @moduledoc false
  alias Bullet.Catalog
  alias Bullet.Catalog.Media
  alias Bullet.Playback.WatchProgress

  def playing(%Media{} = m) do
    m = Bullet.Repo.preload(m, [:collection, :season])

    %{
      id: m.id,
      kind: m.kind,
      title: m.title,
      position: m.position,
      season_number: m.season && m.season.number,
      collection: m.collection && %{title: m.collection.title, slug: m.collection.slug},
      duration_seconds: m.asset.duration_seconds,
      intro_end_seconds: m.intro_end_seconds,
      thumbnail_url: Catalog.thumbnail_for(m)
    }
  end

  def continue_card(%WatchProgress{media: m} = p) do
    %{
      type: "progress",
      id: m.id,
      kind: m.kind,
      title: m.title,
      subtitle: m.collection && m.collection.title,
      description: m.synopsis,
      thumbnail_url: Catalog.thumbnail_for(m),
      duration_seconds: m.asset.duration_seconds,
      position: p.position_seconds
    }
  end
end
