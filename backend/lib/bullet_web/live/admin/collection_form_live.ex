defmodule BulletWeb.Admin.CollectionFormLive do
  @moduledoc "Create / edit a collection (series or anime)."
  use BulletWeb, :live_view

  alias Bullet.Catalog
  alias Bullet.Catalog.Collection

  @impl true
  def mount(params, _session, socket) do
    collection =
      case params do
        %{"id" => id} -> Catalog.get_collection!(id)
        _ -> %Collection{kind: :series}
      end

    {:ok,
     socket
     |> assign(page_title: if(collection.id, do: "Editar coleção", else: "Nova coleção"))
     |> assign(collection: collection, form: to_form(Catalog.change_collection(collection)))}
  end

  @impl true
  def handle_event("validate", %{"collection" => params}, socket) do
    cs = Catalog.change_collection(socket.assigns.collection, params)
    {:noreply, assign(socket, form: to_form(cs, action: :validate))}
  end

  def handle_event("save", %{"collection" => params}, socket) do
    result =
      if socket.assigns.collection.id,
        do: Catalog.update_collection(socket.assigns.collection, params),
        else: Catalog.create_collection(params)

    case result do
      {:ok, c} ->
        {:noreply,
         socket |> put_flash(:info, "Coleção salva.") |> push_navigate(to: ~p"/colecoes/#{c.id}")}

      {:error, cs} ->
        {:noreply, assign(socket, form: to_form(cs))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_admin={@current_admin} active={:catalog}>
      <.link
        navigate={if @collection.id, do: ~p"/colecoes/#{@collection.id}", else: ~p"/"}
        class="text-sm text-muted hover:text-base-content"
      >
        ← Voltar
      </.link>
      <.page_header kicker="Coleção" title={if @collection.id, do: "Editar", else: "Nova coleção"} />

      <.form
        for={@form}
        id="collection-form"
        phx-change="validate"
        phx-submit="save"
        class="panel max-w-2xl space-y-1 p-8"
      >
        <.input
          field={@form[:kind]}
          type="select"
          label="Tipo"
          options={[{"Série", :series}, {"Anime", :anime}]}
        />
        <.input field={@form[:title]} label="Título" required />
        <.input field={@form[:slug]} label="Slug (URL)" placeholder="gerado a partir do título" />
        <.input field={@form[:description]} type="textarea" label="Descrição" rows="4" />
        <.input
          field={@form[:thumbnail_url]}
          label="Miniatura 16:9 (URL https, opcional)"
          placeholder="usa a do primeiro episódio se vazio"
        />
        <.metadata_fields
          form={@form}
          creators_label={if to_string(@form[:kind].value) == "anime", do: "Estúdio", else: "Criação"}
        />
        <div class="pt-4">
          <button type="submit" class="btn btn-accent-outline" phx-disable-with="Salvando…">
            Salvar
          </button>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
