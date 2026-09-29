defmodule Bullet.Playback.SessionReaper do
  @moduledoc """
  Every 30 s, closes playback sessions whose stream is gone without a clean
  channel `terminate/2` (PRD §10.3). Idempotent; safe to run on every node.
  """
  use GenServer
  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, 30_000)
    schedule(interval)
    {:ok, interval}
  end

  @impl true
  def handle_info(:reap, interval) do
    case Bullet.Playback.reap_stale_sessions() do
      [] -> :ok
      stale -> Logger.info("playback: reaped #{length(stale)} stale session(s)")
    end

    schedule(interval)
    {:noreply, interval}
  end

  defp schedule(interval), do: Process.send_after(self(), :reap, interval)
end
