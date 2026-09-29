defmodule Bullet.Workers.PruneTokens do
  @moduledoc "Daily cleanup of expired user tokens."
  use Oban.Worker, queue: :default

  @impl Oban.Worker
  def perform(_job) do
    Bullet.Accounts.prune_expired_tokens()
    :ok
  end
end
