defmodule Bullet.Billing.Subscription do
  @moduledoc false
  use Bullet.Schema

  @type t :: %__MODULE__{}

  schema "subscriptions" do
    field :status, Ecto.Enum, values: [:trialing, :active, :past_due, :canceled]
    field :gateway, :string
    field :gateway_ref, :string
    field :current_period_end, :utc_datetime_usec

    belongs_to :user, Bullet.Accounts.User
    belongs_to :plan, Bullet.Billing.Plan

    timestamps()
  end
end
