defmodule Bullet.Catalog.Collection do
  @moduledoc "A series or an anime: collection → seasons → episodes."
  use Bullet.Schema

  require Bullet.Catalog.Metadata
  alias Bullet.Catalog.Metadata

  @type t :: %__MODULE__{}

  schema "collections" do
    field :kind, Ecto.Enum, values: [:series, :anime]
    field :title, :string
    field :slug, :string
    field :description, :string
    field :thumbnail_url, :string
    field :published_at, :utc_datetime_usec
    Metadata.schema_fields()

    has_many :seasons, Bullet.Catalog.Season, preload_order: [asc: :number]
    has_many :media, Bullet.Catalog.Media

    timestamps()
  end

  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:kind, :title, :slug, :description, :thumbnail_url])
    |> validate_required([:kind, :title])
    |> validate_length(:title, max: 160)
    |> put_slug()
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/,
      message: "use letras minúsculas, números e hífens"
    )
    |> validate_url(:thumbnail_url)
    |> Metadata.changeset(attrs)
    |> unique_constraint(:slug, message: "já está em uso")
  end

  defp put_slug(changeset) do
    case {get_field(changeset, :slug), get_change(changeset, :title)} do
      {slug, title} when slug in [nil, ""] and is_binary(title) ->
        put_change(changeset, :slug, slugify(title))

      _ ->
        changeset
    end
  end

  @doc ~S|`"A Série: Temporada Ação!"` → `"a-serie-temporada-acao"`.|
  def slugify(text) do
    text
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  @doc false
  def validate_url(changeset, field) do
    validate_change(changeset, field, fn ^field, url ->
      case URI.parse(url) do
        # An https URL (Bunny thumbnails, external art)…
        %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> []
        # …or a same-origin root-relative asset path (locally hosted covers).
        %URI{scheme: nil, host: nil, path: "/" <> _} -> []
        _ -> [{field, "use uma URL https ou um caminho começando com /"}]
      end
    end)
  end
end
