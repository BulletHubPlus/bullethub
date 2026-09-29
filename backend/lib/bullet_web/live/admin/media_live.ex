defmodule BulletWeb.Admin.MediaLive do
  @moduledoc """
  Create/edit a movie or episode, upload its video straight to Bunny
  (TUS, resumable) and publish it. Encoding status updates live via PubSub (RF10).
  """
  use BulletWeb, :live_view

  alias Bullet.{Catalog, Ingest}
  alias Bullet.Catalog.Media
  alias Bullet.Media.Provider

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(simulated?: Provider.impl() == Bullet.Media.Fake, upload_pct: nil, captions: [])
      |> allow_upload(:caption, accept: ~w(.vtt .srt), max_entries: 1, max_file_size: 2_000_000)

    case params do
      %{"id" => id} ->
        if connected?(socket), do: Ingest.subscribe()
        {:ok, load(socket, id)}

      %{"season_id" => season_id} ->
        season = Bullet.Repo.get!(Catalog.Season, season_id) |> Bullet.Repo.preload(:collection)

        media = %Media{
          kind: :episode,
          season: season,
          collection: season.collection,
          asset: nil,
          position: Catalog.next_position(season)
        }

        {:ok, assign_new_media(socket, media, season)}

      _ ->
        {:ok,
         assign_new_media(
           socket,
           %Media{kind: :movie, collection: nil, season: nil, asset: nil},
           nil
         )}
    end
  end

  defp assign_new_media(socket, media, season) do
    assign(socket,
      media: media,
      season: season,
      page_title: "Novo #{String.downcase(kind_label(media.kind))}",
      form: to_form(Catalog.change_media(media))
    )
  end

  defp load(socket, id) do
    media = Catalog.get_media!(id)

    assign(socket,
      media: media,
      season: media.season,
      page_title: media.title,
      form: to_form(Catalog.change_media(media)),
      captions: Catalog.list_captions(media)
    )
  end

  ## Form

  @impl true
  def handle_event("validate", %{"media" => params}, socket) do
    cs = Catalog.change_media(socket.assigns.media, params)
    {:noreply, assign(socket, form: to_form(cs, action: :validate))}
  end

  def handle_event("save", %{"media" => params}, socket) do
    %{media: media, season: season} = socket.assigns

    result =
      cond do
        media.id -> Catalog.update_media(media, params)
        season -> Catalog.create_item(season, params)
        true -> Catalog.create_movie(params)
      end

    case result do
      {:ok, saved} ->
        socket =
          put_flash(
            socket,
            :info,
            if(media.id, do: "Salvo.", else: "Criado. Agora envie o vídeo.")
          )

        {:noreply,
         if(media.id,
           do: load(socket, saved.id),
           else: push_navigate(socket, to: ~p"/midias/#{saved.id}")
         )}

      {:error, cs} ->
        {:noreply, assign(socket, form: to_form(cs))}
    end
  end

  ## Upload (TusUpload hook, assets/js/hooks/tus_upload.js)

  def handle_event("request_upload", _params, socket) do
    case Ingest.start_upload(socket.assigns.media) do
      {:ok, _asset, creds} ->
        {:reply, %{credentials: creds}, socket |> assign(upload_pct: 0) |> reload()}

      {:error, :already_uploaded} ->
        {:reply, %{error: "Este item já tem vídeo."}, socket}

      {:error, reason} ->
        {:reply, %{error: "Não foi possível iniciar o envio (#{inspect(reason)})."}, socket}
    end
  end

  def handle_event("upload_progress", %{"pct" => pct}, socket) when is_number(pct) do
    {:noreply, assign(socket, upload_pct: pct)}
  end

  def handle_event("upload_complete", _params, socket) do
    socket = reload(socket)
    if socket.assigns.media.asset, do: Ingest.mark_uploaded(socket.assigns.media.asset)
    {:noreply, socket |> assign(upload_pct: nil) |> reload()}
  end

  def handle_event("upload_error", %{"message" => message}, socket) do
    {:noreply,
     socket
     |> assign(upload_pct: nil)
     |> put_flash(
       :error,
       "Envio interrompido: #{message}. Selecione o mesmo arquivo para retomar."
     )}
  end

  def handle_event("simulate", _params, socket) do
    with {:ok, asset, _} <- Ingest.start_upload(socket.assigns.media),
         {:ok, asset} <- Ingest.mark_uploaded(asset),
         {:ok, _} <- Ingest.simulate_encoding(asset) do
      {:noreply, socket |> put_flash(:info, "Encoding simulado (provider Fake).") |> reload()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Não foi possível simular.")}
    end
  end

  ## Captions

  def handle_event("validate_caption", _params, socket), do: {:noreply, socket}

  # File.read! below reads LiveView's own temp file for the upload, never a user path.
  # sobelow_skip ["Traversal.FileModule"]
  def handle_event("save_caption", %{"srclang" => srclang}, socket) do
    results =
      consume_uploaded_entries(socket, :caption, fn %{path: path}, _entry ->
        {:ok, Catalog.put_caption(socket.assigns.media, srclang, File.read!(path))}
      end)

    socket =
      case results do
        [{:ok, _}] ->
          put_flash(socket, :info, "Legenda salva.")

        [{:error, :no_video}] ->
          put_flash(socket, :error, "Envie o vídeo antes da legenda.")

        [{:error, :invalid_file}] ->
          put_flash(socket, :error, "Arquivo inválido: use .srt ou .vtt em UTF-8.")

        [{:error, _}] ->
          put_flash(socket, :error, "Não foi possível salvar a legenda.")

        [] ->
          put_flash(socket, :error, "Selecione um arquivo.")
      end

    {:noreply, reload(socket)}
  end

  def handle_event("delete_caption", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.captions, &(&1.id == id)) do
      nil -> :ok
      caption -> Catalog.delete_caption(caption)
    end

    {:noreply, reload(socket)}
  end

  ## Publish / delete

  def handle_event("publish", _params, socket) do
    case Catalog.publish_media(socket.assigns.media) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Publicado.") |> reload()}

      {:error, :asset_not_ready} ->
        {:noreply, put_flash(socket, :error, "Só é possível publicar com o vídeo pronto.")}
    end
  end

  def handle_event("unpublish", _params, socket) do
    {:ok, _} = Catalog.unpublish_media(socket.assigns.media)
    {:noreply, reload(socket)}
  end

  def handle_event("delete", _params, socket) do
    media = socket.assigns.media
    {:ok, _} = Catalog.delete_media(media)
    back = if media.collection_id, do: ~p"/colecoes/#{media.collection_id}", else: ~p"/"
    {:noreply, socket |> put_flash(:info, "Removido.") |> push_navigate(to: back)}
  end

  @impl true
  def handle_info({:asset_status, %{media_id: id}}, %{assigns: %{media: %{id: id}}} = socket) do
    {:noreply, reload(socket)}
  end

  def handle_info({:asset_status, _}, socket), do: {:noreply, socket}

  defp reload(%{assigns: %{media: %{id: id}}} = socket) when is_binary(id), do: load(socket, id)
  defp reload(socket), do: socket

  ## View

  defp back_path(%Media{collection_id: nil}), do: ~p"/"
  defp back_path(%Media{collection_id: id}), do: ~p"/colecoes/#{id}"

  defp can_upload?(%Media{asset: nil}), do: true
  defp can_upload?(%Media{asset: %{status: status}}), do: status in [:uploading, :failed]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_admin={@current_admin} active={:catalog}>
      <.link navigate={back_path(@media)} class="text-sm text-muted hover:text-base-content">
        ← {if @media.collection, do: @media.collection.title, else: "Catálogo"}
      </.link>
      <.page_header
        kicker={kind_label(@media.kind) <> if(@season, do: " · #{season_label(@media.collection.kind)} #{@season.number}", else: "")}
        title={@media.title || "Novo #{String.downcase(kind_label(@media.kind))}"}
      >
        <:actions :if={@media.id}>
          <button
            :if={!@media.published_at}
            id="publish"
            phx-click="publish"
            class="btn btn-accent-outline"
            disabled={!(@media.asset && @media.asset.status == :ready)}
          >
            Publicar
          </button>
          <button
            :if={@media.published_at}
            id="unpublish"
            phx-click="unpublish"
            class="btn btn-ghost border border-hairline"
          >
            Despublicar
          </button>
        </:actions>
      </.page_header>

      <div class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_380px]">
        <.form
          for={@form}
          id="media-form"
          phx-change="validate"
          phx-submit="save"
          class="panel space-y-1 p-8"
        >
          <.input field={@form[:title]} label="Título" required />
          <.input field={@form[:synopsis]} type="textarea" label="Sinopse" rows="4" />
          <div class="grid gap-4 sm:grid-cols-2">
            <.input
              :if={@media.kind != :movie}
              field={@form[:position]}
              type="number"
              label="Posição"
              min="1"
            />
            <.input
              field={@form[:intro_end_seconds]}
              type="number"
              label="Fim da abertura (s)"
              min="0"
            />
          </div>
          <.input
            field={@form[:thumbnail_url]}
            label="Miniatura (URL https, opcional)"
            placeholder="usa a gerada pelo Bunny se vazio"
          />
          <.metadata_fields :if={@media.kind == :movie} form={@form} creators_label="Direção" />
          <div class="pt-4">
            <button type="submit" class="btn btn-accent-outline" phx-disable-with="Salvando…">
              {if @media.id, do: "Salvar", else: "Criar e enviar vídeo"}
            </button>
          </div>
        </.form>

        <section :if={@media.id} class="panel p-6" id="video-panel">
          <div class="flex items-center justify-between">
            <h2 class="sec-label flex-1">Vídeo</h2>
            <.asset_status asset={@media.asset} />
          </div>

          <div
            :if={@media.asset && @media.asset.status == :ready}
            class="mt-6 space-y-4 text-sm"
            id="asset-ready"
          >
            <img
              :if={Catalog.thumbnail_for(@media)}
              src={Catalog.thumbnail_for(@media)}
              alt=""
              class="aspect-video w-full rounded-md border border-hairline object-cover"
            />
            <dl class="grid grid-cols-2 gap-y-2">
              <dt class="text-faint">Duração</dt>
              <dd>{format_duration(@media.asset.duration_seconds)}</dd>
              <dt class="text-faint">Resoluções</dt>
              <dd>{Enum.join(@media.asset.encoded_resolutions, " · ")}</dd>
              <dt class="text-faint">Armazenamento</dt>
              <dd>{format_bytes(@media.asset.storage_bytes)}</dd>
            </dl>
          </div>

          <p :if={@media.asset && @media.asset.status == :processing} class="mt-6 text-sm text-muted">
            O Bunny está codificando. O status muda aqui sozinho quando terminar.
          </p>

          <p :if={@media.asset && @media.asset.status == :failed} class="mt-6 text-sm text-error">
            Falhou ({@media.asset.error}). Envie o arquivo de novo.
          </p>

          <div :if={can_upload?(@media)} class="mt-6">
            <div
              :if={!@simulated?}
              id="tus-upload"
              phx-hook="TusUpload"
              phx-update="ignore"
              class="space-y-3"
            >
              <input
                type="file"
                accept="video/*"
                data-role="file"
                class="file-input file-input-sm w-full"
              />
              <button type="button" data-role="start" class="btn btn-accent-outline w-full">
                <.icon name="hero-arrow-up-tray" class="size-4" />
                <span data-role="label">Enviar para o Bunny</span>
              </button>
              <p class="text-xs text-faint">
                Envio direto ao Bunny, retomável: se fechar a aba, selecione o mesmo arquivo para continuar.
              </p>
            </div>

            <div :if={@upload_pct} class="mt-4" id="upload-progress">
              <div class="h-1.5 overflow-hidden rounded-full bg-base-300">
                <div class="h-full bg-primary transition-all" style={"width: #{@upload_pct}%"}></div>
              </div>
              <p class="mt-2 text-xs tabular-nums text-muted">
                {:erlang.float_to_binary(@upload_pct / 1, decimals: 1)}%
              </p>
            </div>

            <div :if={@simulated?} class="space-y-3">
              <button
                id="simulate"
                phx-click="simulate"
                class="btn btn-ghost w-full border border-dashed border-hairline"
              >
                Simular upload + encoding (dev)
              </button>
              <p class="text-xs text-faint">
                Provider Fake ativo (sem BUNNY_API_KEY). Exporte as variáveis do Bunny para enviar de verdade.
              </p>
            </div>
          </div>
        </section>
      </div>

      <section :if={@media.id} class="panel mt-8 p-6" id="captions-panel">
        <h2 class="sec-label">Legendas</h2>
        <ul :if={@captions != []} class="mt-5 divide-y divide-hairline text-sm">
          <li :for={c <- @captions} id={"caption-#{c.id}"} class="flex items-center gap-4 py-2">
            <span class="w-16 font-mono text-xs text-faint">{c.srclang}</span>
            <span class="flex-1">{c.label}</span>
            <button
              type="button"
              phx-click="delete_caption"
              phx-value-id={c.id}
              data-confirm="Remover esta legenda?"
              class="btn btn-ghost btn-xs text-faint hover:text-error"
            >
              Remover
            </button>
          </li>
        </ul>
        <form
          id="caption-form"
          phx-change="validate_caption"
          phx-submit="save_caption"
          class="mt-5 flex flex-wrap items-end gap-3"
        >
          <select name="srclang" class="select select-sm w-40">
            <option :for={{code, label} <- Bullet.Catalog.Caption.languages()} value={code}>
              {label}
            </option>
          </select>
          <.live_file_input upload={@uploads.caption} class="file-input file-input-sm" />
          <button type="submit" class="btn btn-sm btn-accent-outline">Enviar legenda</button>
          <p :for={err <- upload_errors(@uploads.caption)} class="w-full text-sm text-error">
            {if err == :too_large, do: "Arquivo acima de 2 MB.", else: "Use um arquivo .srt ou .vtt."}
          </p>
        </form>
        <p class="mt-3 text-xs text-faint">
          Uma legenda por idioma; enviar de novo substitui. .srt é convertido para WebVTT.
        </p>
      </section>

      <div :if={@media.id} class="mt-16 border-t border-hairline pt-6">
        <button
          id="delete-media"
          phx-click="delete"
          data-confirm="Remover este item e o vídeo no Bunny? Não dá para desfazer."
          class="btn btn-ghost btn-sm text-faint hover:text-error"
        >
          <.icon name="hero-trash" class="size-4" /> Remover
        </button>
      </div>
    </Layouts.app>
    """
  end
end
