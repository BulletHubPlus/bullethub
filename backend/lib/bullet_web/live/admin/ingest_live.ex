defmodule BulletWeb.Admin.IngestLive do
  @moduledoc "Encoding pipeline at a glance (RF10): every asset and its status, live."
  use BulletWeb, :live_view

  alias Bullet.Ingest

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Ingest.subscribe()
    {:ok, socket |> assign(page_title: "Ingest") |> load()}
  end

  defp load(socket),
    do: assign(socket, assets: Ingest.list_assets(), counts: Ingest.status_counts())

  @impl true
  def handle_info({:asset_status, _asset}, socket), do: {:noreply, load(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_admin={@current_admin} active={:ingest}>
      <.page_header
        kicker="Pipeline"
        title="Ingest"
        subtitle="Uploads e encoding no Bunny. Atualiza sozinho quando um webhook chega."
      />

      <div class="mb-12 grid grid-cols-2 gap-4 sm:grid-cols-4" id="ingest-counts">
        <div
          :for={
            {status, label} <- [
              uploading: "Enviando",
              processing: "Processando",
              ready: "Prontos",
              failed: "Falhas"
            ]
          }
          class="panel p-5"
        >
          <p class="display text-4xl tabular-nums">{Map.get(@counts, status, 0)}</p>
          <p class="mt-2 text-xs font-semibold tracking-wide text-faint">{label}</p>
        </div>
      </div>

      <.sec_label index={length(@assets)} label="Assets recentes" class="mb-4" />
      <div :if={@assets == []} class="panel px-6 py-10 text-center text-muted">
        Nenhum vídeo enviado ainda.
      </div>
      <div :if={@assets != []} class="panel overflow-x-auto">
        <table class="table" id="assets">
          <thead>
            <tr class="text-faint">
              <th>Item</th>
              <th>Status</th>
              <th>Duração</th>
              <th>Tamanho</th>
              <th>Atualizado</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={a <- @assets} id={"asset-#{a.id}"} class="border-hairline">
              <td>
                <.link navigate={~p"/midias/#{a.media_id}"} class="font-semibold hover:text-accent">
                  {a.media.title}
                </.link>
                <p class="text-xs text-faint">
                  {kind_label(a.media.kind)}<span :if={a.media.collection}> · {a.media.collection.title}</span>
                </p>
              </td>
              <td>
                <.asset_status asset={a} />
                <p :if={a.error} class="mt-1 text-xs text-error">{a.error}</p>
              </td>
              <td class="tabular-nums">{format_duration(a.duration_seconds)}</td>
              <td class="tabular-nums">{format_bytes(a.storage_bytes)}</td>
              <td class="text-xs text-faint">
                {Calendar.strftime(a.status_changed_at, "%d/%m %H:%M")}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end
end
