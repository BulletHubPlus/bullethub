defmodule Bullet.Security.SecurityEvent do
  @moduledoc false
  use Bullet.Schema

  schema "security_events" do
    field :kind, :string
    field :ip, :string
    field :user_agent, :string
    field :metadata, :map, default: %{}

    belongs_to :user, Bullet.Accounts.User

    timestamps(updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:user_id, :kind, :ip, :user_agent, :metadata])
    |> validate_required([:kind])
    |> update_change(:user_agent, &String.slice(&1, 0, 255))
  end
end
