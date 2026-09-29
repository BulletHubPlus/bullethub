defmodule Bullet.Billing.Plan do
  @moduledoc false
  use Bullet.Schema

  @type t :: %__MODULE__{}

  schema "plans" do
    field :slug, :string
    field :name, :string
    field :price_cents, :integer
    field :max_streams, :integer
    field :active, :boolean, default: true

    timestamps()
  end
end
