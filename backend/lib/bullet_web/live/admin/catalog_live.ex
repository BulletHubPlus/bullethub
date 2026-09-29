defmodule BulletWeb.Admin.CatalogLive do
  @moduledoc "Catalog overview: collections (series/anime) and movies."
  use BulletWeb, :live_view

  alias Bullet.Catalog

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Catálogo")
     |> assign(collections: Catalog.list_collections(), movies: Catalog.list_movies())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_admin={@current_admin} active={:catalog}>
      <.page_header
        kicker="Conteúdo"
        title="Catálogo"
        subtitle="Séries e animes são coleções com temporadas e episódios. Filmes ficam soltos."
      >
        <:actions>
          <.link navigate={~p"/colecoes/nova"} class="btn btn-accent-outline" id="new-collection">
            <.icon name="hero-plus" class="size-4" /> Nova coleção
          </.link>
          <.link
            navigate={~p"/midias/nova"}
            class="btn btn-ghost border border-hairline"
            id="new-movie"
          >
            <.icon name="hero-plus" class="size-4" /> Novo filme
          </.link>
        </:actions>
      </.page_header>

      <.sec_label index={length(@collections)} label="Coleções" class="mb-4" />
      <div
        :if={@collections == []}
        class="panel px-6 py-10 text-center text-muted"
        id="collections-empty"
      >
        Nenhuma coleção ainda.
      </div>
      <div :if={@collections != []} class="panel overflow-hidden" id="collections">
        <.link
          :for={%{collection: c, media_count: n} <- @collections}
          navigate={~p"/colecoes/#{c.id}"}
          id={"collection-#{c.id}"}
          class="flex items-center gap-5 border-b border-hairline px-6 py-4 transition last:border-0 hover:bg-base-300/40"
        >
          <div class="min-w-0 flex-1">
            <p class="font-semibold">{c.title}</p>
            <p class="mt-0.5 text-xs text-faint">
              {kind_label(c.kind)} · {n} {if n == 1, do: "item", else: "itens"} · /{c.slug}
            </p>
          </div>
          <.published_badge published_at={c.published_at} />
          <.icon name="hero-chevron-right" class="size-4 text-faint" />
        </.link>
      </div>

      <.sec_label index={length(@movies)} label="Filmes" class="mt-14 mb-4" />
      <div :if={@movies == []} class="panel px-6 py-10 text-center text-muted" id="movies-empty">
        Nenhum filme ainda.
      </div>
      <div :if={@movies != []} class="panel overflow-hidden" id="movies">
        <.link
          :for={m <- @movies}
          navigate={~p"/midias/#{m.id}"}
          id={"movie-#{m.id}"}
          class="flex items-center gap-5 border-b border-hairline px-6 py-4 transition last:border-0 hover:bg-base-300/40"
        >
          <div class="min-w-0 flex-1">
            <p class="font-semibold">{m.title}</p>
            <p class="mt-0.5 text-xs text-faint">
              {format_duration(m.asset && m.asset.duration_seconds)}
            </p>
          </div>
          <.asset_status asset={m.asset} />
          <.published_badge published_at={m.published_at} />
          <.icon name="hero-chevron-right" class="size-4 text-faint" />
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
