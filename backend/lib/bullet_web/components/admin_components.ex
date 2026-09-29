defmodule BulletWeb.AdminComponents do
  @moduledoc "Small building blocks for the admin panel."
  use Phoenix.Component

  import BulletWeb.CoreComponents, only: [input: 1, translate_error: 1]

  alias Bullet.Catalog.{Genres, Metadata}
  alias Bullet.Ingest.MediaAsset

  @status %{
    nil => {"Sem vídeo", "bg-base-300"},
    uploading: {"Enviando", "bg-info"},
    processing: {"Processando", "bg-warning animate-pulse"},
    ready: {"Pronto", "bg-success"},
    failed: {"Falhou", "bg-error"}
  }

  @doc "Page header: kicker + display title + optional actions."
  attr :kicker, :string, default: nil
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :actions

  def page_header(assigns) do
    ~H"""
    <header class="mb-10 flex flex-wrap items-end justify-between gap-6">
      <div>
        <p :if={@kicker} class="kicker"><span class="diamond" />{@kicker}</p>
        <h1 class="display mt-4 text-4xl sm:text-5xl">{@title}<span class="text-primary">.</span></h1>
        <p :if={@subtitle} class="mt-3 max-w-[60ch] text-muted">{@subtitle}</p>
      </div>
      <div :if={@actions != []} class="flex gap-3">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Title metadata block (collections and movies): year, rating, genres, cast,
  creators, poster and backdrop. `creators_label` is "Estúdio" for anime.
  """
  attr :form, Phoenix.HTML.Form, required: true
  attr :creators_label, :string, default: "Direção / criação"

  def metadata_fields(assigns) do
    assigns =
      assign(assigns,
        selected: MapSet.new(assigns.form[:genres].value || []),
        genres: Genres.all(),
        ratings: Metadata.age_ratings()
      )

    ~H"""
    <fieldset class="space-y-1 border-t border-hairline pt-6" id="metadata-fields">
      <legend class="sec-label mb-4 w-full">Ficha técnica</legend>
      <div class="grid gap-4 sm:grid-cols-[1fr_120px_140px]">
        <.input field={@form[:original_title]} label="Título original" />
        <.input field={@form[:release_year]} type="number" label="Ano" min="1888" />
        <.input
          field={@form[:age_rating]}
          type="select"
          label="Classificação"
          prompt="-"
          options={Enum.map(@ratings, &{if(&1 == "L", do: "Livre", else: "#{&1} anos"), &1})}
        />
      </div>

      <div class="fieldset mb-2">
        <span class="label mb-2">Gêneros</span>
        <input type="hidden" name={@form[:genres].name <> "[]"} value="" />
        <div class="flex flex-wrap gap-2">
          <label
            :for={{slug, label} <- @genres}
            class={[
              "cursor-pointer rounded-md border px-3 py-1.5 text-xs font-semibold transition",
              if(MapSet.member?(@selected, slug),
                do: "border-primary/60 bg-primary/10 text-accent",
                else: "border-hairline text-muted hover:text-base-content"
              )
            ]}
          >
            <input
              type="checkbox"
              class="sr-only"
              name={@form[:genres].name <> "[]"}
              value={slug}
              checked={MapSet.member?(@selected, slug)}
            />
            {label}
          </label>
        </div>
        <p
          :for={msg <- Enum.map(@form[:genres].errors, &translate_error/1)}
          class="mt-1.5 text-sm text-error"
        >
          {msg}
        </p>
      </div>

      <.input
        field={@form[:cast]}
        value={Metadata.join(@form[:cast].value)}
        label="Elenco (separado por vírgula)"
        placeholder="Nome Um, Nome Dois"
      />
      <.input
        field={@form[:creators]}
        value={Metadata.join(@form[:creators].value)}
        label={@creators_label <> " (separado por vírgula)"}
      />
      <div class="grid gap-4 sm:grid-cols-2">
        <.input field={@form[:poster_url]} label="Pôster vertical 2:3 (URL https)" />
        <.input field={@form[:backdrop_url]} label="Imagem de fundo 16:9 (URL https)" />
      </div>
    </fieldset>
    """
  end

  attr :asset, :any, required: true, doc: "a MediaAsset or nil"

  def asset_status(assigns) do
    status = if match?(%MediaAsset{}, assigns.asset), do: assigns.asset.status
    {label, dot} = Map.fetch!(@status, status)
    assigns = assign(assigns, label: label, dot: dot, status: status || :none)

    ~H"""
    <span
      class="inline-flex items-center gap-2 text-xs font-semibold text-muted"
      data-status={@status}
    >
      <span class={["status-dot", @dot]}></span>{@label}
    </span>
    """
  end

  attr :published_at, :any, required: true

  def published_badge(assigns) do
    ~H"""
    <span
      :if={@published_at}
      class="rounded border border-primary/50 px-2 py-0.5 text-[10.5px] font-bold uppercase tracking-[0.14em] text-accent"
    >
      Publicado
    </span>
    <span
      :if={!@published_at}
      class="rounded border border-hairline px-2 py-0.5 text-[10.5px] font-bold uppercase tracking-[0.14em] text-faint"
    >
      Rascunho
    </span>
    """
  end

  attr :index, :integer, required: true
  attr :label, :string, required: true
  attr :class, :string, default: nil

  def sec_label(assigns) do
    ~H"""
    <h2 class={["sec-label", @class]}>
      <span class="idx">{String.pad_leading(Integer.to_string(@index), 2, "0")}</span>{@label}
    </h2>
    """
  end

  def format_duration(nil), do: "-"

  def format_duration(seconds) do
    h = div(seconds, 3600)
    m = div(rem(seconds, 3600), 60)
    s = rem(seconds, 60)
    if h > 0, do: "#{h}h#{pad(m)}", else: "#{m}:#{pad(s)}"
  end

  def format_bytes(nil), do: "-"
  def format_bytes(b) when b >= 1_073_741_824, do: "#{Float.round(b / 1_073_741_824, 1)} GB"
  def format_bytes(b) when b >= 1_048_576, do: "#{Float.round(b / 1_048_576, 1)} MB"
  def format_bytes(b), do: "#{div(b, 1024)} KB"

  def kind_label(:series), do: "Série"
  def kind_label(:anime), do: "Anime"
  def kind_label(:movie), do: "Filme"
  def kind_label(:episode), do: "Episódio"

  def season_label(_kind), do: "Temporada"

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")
end
