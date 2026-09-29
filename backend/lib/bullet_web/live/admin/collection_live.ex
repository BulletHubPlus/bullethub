defmodule BulletWeb.Admin.CollectionLive do
  @moduledoc "A collection with its seasons/modules and items, with live encoding status."
  use BulletWeb, :live_view

  alias Bullet.{Catalog, Ingest}
  alias Bullet.Catalog.Season

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket), do: Ingest.subscribe()

    {:ok, socket |> load(id) |> assign_season_form()}
  end

  defp load(socket, id) do
    c = Catalog.get_collection!(id)
    assign(socket, collection: c, page_title: c.title, media_ids: media_ids(c))
  end

  defp media_ids(c), do: for(s <- c.seasons, m <- s.media, into: MapSet.new(), do: m.id)

  defp assign_season_form(socket) do
    number = Catalog.next_season_number(socket.assigns.collection)
    assign(socket, season_form: to_form(Catalog.change_season(%Season{}, %{number: number})))
  end

  @impl true
  def handle_event("add_season", %{"season" => params}, socket) do
    case Catalog.create_season(socket.assigns.collection, params) do
      {:ok, _} -> {:noreply, socket |> load(socket.assigns.collection.id) |> assign_season_form()}
      {:error, cs} -> {:noreply, assign(socket, season_form: to_form(cs))}
    end
  end

  def handle_event("delete_season", %{"id" => id}, socket) do
    season = Enum.find(socket.assigns.collection.seasons, &(&1.id == id))
    {:ok, _} = Catalog.delete_season(season)
    {:noreply, socket |> load(socket.assigns.collection.id) |> assign_season_form()}
  end

  def handle_event("toggle_publish", _params, socket) do
    c = socket.assigns.collection
    {:ok, _} = Catalog.set_collection_published(c, is_nil(c.published_at))
    {:noreply, load(socket, c.id)}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Catalog.delete_collection(socket.assigns.collection)
    {:noreply, socket |> put_flash(:info, "Coleção removida.") |> push_navigate(to: ~p"/")}
  end

  @impl true
  def handle_info({:asset_status, asset}, socket) do
    if MapSet.member?(socket.assigns.media_ids, asset.media_id),
      do: {:noreply, load(socket, socket.assigns.collection.id)},
      else: {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_admin={@current_admin} active={:catalog}>
      <.link navigate={~p"/"} class="text-sm text-muted hover:text-base-content">← Catálogo</.link>
      <.page_header
        kicker={kind_label(@collection.kind)}
        title={@collection.title}
        subtitle={@collection.description}
      >
        <:actions>
          <button id="toggle-publish" phx-click="toggle_publish" class="btn btn-accent-outline">
            {if @collection.published_at, do: "Despublicar", else: "Publicar"}
          </button>
          <.link
            navigate={~p"/colecoes/#{@collection.id}/editar"}
            class="btn btn-ghost border border-hairline"
          >
            Editar
          </.link>
        </:actions>
      </.page_header>

      <div class="mb-10 flex items-center gap-3 text-sm text-muted">
        <.published_badge published_at={@collection.published_at} /> <span>/{@collection.slug}</span>
        <span :if={@collection.published_at} class="text-faint">
          · só aparece para assinantes depois que tiver pelo menos um item publicado e pronto
        </span>
      </div>

      <section :for={season <- @collection.seasons} id={"season-#{season.id}"} class="mb-12">
        <div class="mb-4 flex items-center gap-4">
          <.sec_label
            index={season.number}
            label={season.title || "#{season_label(@collection.kind)} #{season.number}"}
            class="flex-1"
          />
          <.link
            navigate={~p"/midias/nova?season_id=#{season.id}"}
            class="btn btn-ghost btn-sm border border-hairline"
            id={"add-item-#{season.id}"}
          >
            <.icon name="hero-plus" class="size-4" /> Episódio
          </.link>
          <button
            phx-click="delete_season"
            phx-value-id={season.id}
            data-confirm="Remover a temporada e todos os vídeos dele (inclusive no Bunny)?"
            class="btn btn-ghost btn-sm text-faint hover:text-error"
            aria-label="Remover"
          >
            <.icon name="hero-trash" class="size-4" />
          </button>
        </div>

        <div :if={season.media == []} class="panel px-6 py-6 text-sm text-muted">
          Nenhum item ainda.
        </div>
        <div :if={season.media != []} class="panel overflow-hidden">
          <.link
            :for={m <- season.media}
            navigate={~p"/midias/#{m.id}"}
            id={"media-#{m.id}"}
            class="flex items-center gap-5 border-b border-hairline px-6 py-4 transition last:border-0 hover:bg-base-300/40"
          >
            <span class="w-8 text-sm font-bold tabular-nums text-primary">
              {String.pad_leading("#{m.position}", 2, "0")}
            </span>
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
      </section>

      <.form
        for={@season_form}
        id="season-form"
        phx-submit="add_season"
        class="panel flex flex-wrap items-end gap-4 p-6"
      >
        <div class="w-28">
          <.input field={@season_form[:number]} type="number" label="Número" min="1" />
        </div>
        <div class="min-w-56 flex-1">
          <.input
            field={@season_form[:title]}
            label="Título (opcional)"
            placeholder={"#{season_label(@collection.kind)} #{@season_form[:number].value}"}
          />
        </div>
        <button type="submit" class="btn btn-ghost mb-2 border border-hairline">
          <.icon name="hero-plus" class="size-4" />
          Adicionar {String.downcase(season_label(@collection.kind))}
        </button>
      </.form>

      <div class="mt-16 border-t border-hairline pt-6">
        <button
          id="delete-collection"
          phx-click="delete"
          data-confirm="Remover a coleção inteira e todos os vídeos (inclusive no Bunny)? Não dá para desfazer."
          class="btn btn-ghost btn-sm text-faint hover:text-error"
        >
          <.icon name="hero-trash" class="size-4" /> Remover coleção
        </button>
      </div>
    </Layouts.app>
    """
  end
end
