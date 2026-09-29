defmodule Bullet.Catalog.Media do
  @moduledoc "A playable item: movie (standalone) or episode (inside a season)."
  use Bullet.Schema

  require Bullet.Catalog.Metadata
  alias Bullet.Catalog.{Collection, Metadata}

  @type t :: %__MODULE__{}

  schema "media" do
    field :kind, Ecto.Enum, values: [:movie, :episode]
    field :position, :integer
    field :title, :string
    field :synopsis, :string
    field :thumbnail_url, :string
    field :intro_end_seconds, :integer
    field :published_at, :utc_datetime_usec
    Metadata.schema_fields()

    belongs_to :collection, Bullet.Catalog.Collection
    belongs_to :season, Bullet.Catalog.Season
    has_one :asset, Bullet.Ingest.MediaAsset

    timestamps()
  end

  @doc "`collection_id`/`season_id`/`kind` are set by the context, never cast from params."
  def changeset(media, attrs) do
    media
    |> cast(attrs, [:position, :title, :synopsis, :thumbnail_url, :intro_end_seconds])
    |> validate_required([:title])
    |> validate_length(:title, max: 160)
    |> validate_number(:intro_end_seconds, greater_than_or_equal_to: 0)
    |> validate_number(:position, greater_than: 0)
    |> Collection.validate_url(:thumbnail_url)
    |> cast_movie_metadata(attrs)
    |> validate_position()
    |> unique_constraint([:season_id, :position], message: "já existe nesta temporada")
    |> check_constraint(:kind,
      name: :movie_without_collection,
      message: "filme não pode pertencer a uma coleção"
    )
  end

  # Year, rating, genres, cast… describe a title; for episodes the collection carries them.
  defp cast_movie_metadata(changeset, attrs) do
    if get_field(changeset, :kind) == :movie,
      do: Metadata.changeset(changeset, attrs),
      else: changeset
  end

  defp validate_position(changeset) do
    if get_field(changeset, :kind) == :movie,
      do: changeset,
      else: validate_required(changeset, [:position])
  end
end
