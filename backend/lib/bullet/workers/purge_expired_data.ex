defmodule Bullet.Workers.PurgeExpiredData do
  @moduledoc "Daily LGPD retention (PRD §12): see `Bullet.Accounts.Privacy.purge_expired/0`."
  use Oban.Worker, queue: :default, unique: [period: 3600]

  require Logger
  alias Bullet.Accounts.Privacy

  @impl Oban.Worker
  def perform(_job) do
    counts = Privacy.purge_expired()
    Logger.info("privacy: retention purge #{inspect(counts)}")
    :ok
  end
end
