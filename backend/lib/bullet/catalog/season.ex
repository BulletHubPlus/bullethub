defmodule Bullet.Catalog.Season do
  @moduledoc "A season of a series or anime."
  use Bullet.Schema

  @type t :: %__MODULE__{}

  schema "seasons" do
    field :number, :integer
    field :title, :string

    belongs_to :collection, Bullet.Catalog.Collection
    has_many :media, Bullet.Catalog.Media, preload_order: [asc: :position]

    timestamps()
  end

  def changeset(season, attrs) do
    season
    |> cast(attrs, [:number, :title])
    |> validate_required([:number])
    |> validate_number(:number, greater_than: 0)
    |> unique_constraint([:collection_id, :number], message: "já existe")
  end
end
