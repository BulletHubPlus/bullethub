defmodule Bullet.Workers.AssetStatusPoller do
  @moduledoc "Every 10 min: reconcile assets whose webhook never arrived (PRD §15)."
  use Oban.Worker, queue: :default, unique: [period: 300]

  @impl Oban.Worker
  def perform(_job) do
    Bullet.Ingest.reconcile_stuck_assets()
    :ok
  end
end
