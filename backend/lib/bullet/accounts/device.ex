defmodule Bullet.Accounts.Device do
  @moduledoc false
  use Bullet.Schema

  @type t :: %__MODULE__{}

  schema "devices" do
    field :name, :string
    field :user_agent, :string
    field :last_seen_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    belongs_to :user, Bullet.Accounts.User

    timestamps()
  end

  def create_changeset(device, attrs) do
    device
    |> cast(attrs, [:name, :user_agent])
    |> update_change(:user_agent, &String.slice(&1, 0, 255))
    |> update_change(:name, &String.slice(&1, 0, 80))
    |> validate_required([:name])
  end
end
