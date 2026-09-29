defmodule Bullet.Ingest.WebhookEvent do
  @moduledoc "Inbox for provider webhooks. Unique `(provider, event_id)` makes delivery idempotent."
  use Bullet.Schema

  @type t :: %__MODULE__{}

  schema "webhook_events" do
    field :provider, :string
    field :event_id, :string
    field :payload, :map
    field :processed_at, :utc_datetime_usec
    field :error, :string

    timestamps()
  end
end
