defmodule Bullet.Workers.ProcessWebhookEvent do
  @moduledoc "Applies a stored webhook event. Enqueued in the same transaction as the insert."
  use Oban.Worker,
    queue: :default,
    max_attempts: 10,
    unique: [keys: [:webhook_event_id], period: :infinity]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"webhook_event_id" => id}}) do
    case Bullet.Ingest.process_webhook_event(id) do
      # Unknown video / impossible transition are recorded on the event, not retried.
      {:error, reason} when reason in [:unknown_video, :invalid_transition] -> :ok
      {:error, reason} -> {:error, reason}
      _ -> :ok
    end
  end
end
