defmodule BulletWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use BulletWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Admin shell: sidebar navigation + content. Pass `active` to highlight the
  current section.
  """
  attr :flash, :map, required: true
  attr :current_admin, :map, required: true
  attr :active, :atom, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex min-h-dvh">
      <aside class="sticky top-0 hidden h-dvh w-60 shrink-0 flex-col border-r border-hairline bg-base-100 px-5 py-6 lg:flex">
        <.link navigate={~p"/"} class="wordmark inline-flex items-center gap-2">
          <img src={~p"/images/logo-mark.webp"} alt="" class="size-7 mix-blend-screen" />
          <span>
            bullethub<span class="dot">.</span>
          </span>
        </.link>
        <span class="kicker mt-2 !text-[10px]"><span class="diamond" />Admin</span>

        <nav class="mt-10 flex flex-col gap-1 text-sm" aria-label="Admin">
          <.nav_item
            :if={@current_admin.role in [:owner, :editor]}
            href={~p"/"}
            icon="hero-film"
            active={@active == :catalog}
          >
            Catálogo
          </.nav_item>
          <.nav_item href={~p"/ingest"} icon="hero-arrow-up-tray" active={@active == :ingest}>
            Ingest
          </.nav_item>
          <.nav_item
            :if={@current_admin.role in [:owner, :support]}
            href={~p"/usuarios"}
            icon="hero-users"
            active={@active == :users}
          >
            Usuários
          </.nav_item>
        </nav>

        <div class="mt-auto border-t border-hairline pt-5 text-xs">
          <p class="truncate text-muted">{@current_admin.email}</p>
          <p class="mt-1 uppercase tracking-[0.14em] text-faint">{@current_admin.role}</p>
          <.link href={~p"/logout"} method="delete" class="btn btn-ghost btn-sm mt-4 -ml-3 text-muted">
            <.icon name="hero-arrow-left-on-rectangle" class="size-4" /> Sair
          </.link>
        </div>
      </aside>

      <div class="min-w-0 flex-1">
        <header class="flex items-center justify-between border-b border-hairline px-5 py-4 lg:hidden">
          <.link navigate={~p"/"} class="wordmark inline-flex items-center gap-2">
            <img src={~p"/images/logo-mark.webp"} alt="" class="size-7 mix-blend-screen" />
            <span>
              bullethub<span class="dot">.</span>
            </span>
          </.link>
          <nav class="flex gap-4 text-sm">
            <.link :if={@current_admin.role in [:owner, :editor]} navigate={~p"/"}>Catálogo</.link>
            <.link navigate={~p"/ingest"}>Ingest</.link>
            <.link :if={@current_admin.role in [:owner, :support]} navigate={~p"/usuarios"}>
              Usuários
            </.link>
          </nav>
        </header>
        <main class="glow-top px-5 py-10 sm:px-10">
          <div class="mx-auto max-w-6xl">
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp nav_item(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-3 rounded-md px-3 py-2 transition",
        if(@active,
          do: "bg-base-200 text-base-content shadow-[inset_2px_0_0_#f20024]",
          else: "text-muted hover:bg-base-200 hover:text-base-content"
        )
      ]}
    >
      <.icon name={@icon} class="size-4" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="Sem conexão com a internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Tentando reconectar
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Algo deu errado"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Tentando reconectar
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
