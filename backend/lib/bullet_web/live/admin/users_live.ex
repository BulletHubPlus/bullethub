defmodule BulletWeb.Admin.UsersLive do
  @moduledoc "Account search: e-mail, id, or the 6-char code from a watermark (RF06)."
  use BulletWeb, :live_view

  alias Bullet.Support

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Usuários", query: "", hits: nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = params["q"] || ""
    hits = if query == "", do: nil, else: Support.search(query)
    {:noreply, assign(socket, query: query, hits: hits)}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, push_patch(socket, to: ~p"/usuarios?#{%{q: String.trim(q)}}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_admin={@current_admin} active={:users}>
      <.page_header
        kicker="Suporte"
        title="Usuários"
        subtitle="Busque por e-mail, id ou pelo código de 6 caracteres que aparece na marca d'água de um vídeo vazado."
      />

      <.form for={%{}} as={:search} id="user-search" phx-submit="search" class="panel flex gap-3 p-4">
        <input
          type="search"
          name="q"
          value={@query}
          placeholder="email@exemplo.com  ·  7K3Q9F"
          autocomplete="off"
          class="input w-full"
          autofocus
        />
        <button type="submit" class="btn btn-accent-outline">Buscar</button>
      </.form>

      <div :if={@hits == []} class="panel mt-6 px-6 py-10 text-center text-muted" id="no-hits">
        Nada encontrado para "{@query}".
      </div>

      <div :if={@hits not in [nil, []]} class="panel mt-6 overflow-hidden" id="hits">
        <.link
          :for={%{user: u, matched_code: s} <- @hits}
          navigate={~p"/usuarios/#{u.id}"}
          id={"user-#{u.id}"}
          class="flex items-center gap-5 border-b border-hairline px-6 py-4 transition last:border-0 hover:bg-base-300/40"
        >
          <div class="min-w-0 flex-1">
            <p class="font-semibold">{u.name}</p>
            <p class="mt-0.5 truncate text-xs text-faint">{u.email}</p>
            <p :if={s} class="mt-2 text-xs text-accent" id="matched-code">
              Código {s.code} · {s.media && s.media.title} · {Calendar.strftime(
                s.started_at,
                "%d/%m/%Y %H:%M"
              )}
            </p>
          </div>
          <span :if={u.deleted_at} class="text-xs font-bold uppercase tracking-[0.14em] text-faint">
            Apagada
          </span>
          <span
            :if={u.suspended_at && !u.deleted_at}
            class="text-xs font-bold uppercase tracking-[0.14em] text-error"
          >
            Suspensa
          </span>
          <.icon name="hero-chevron-right" class="size-4 text-faint" />
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
