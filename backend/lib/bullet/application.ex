defmodule Bullet.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        BulletWeb.Telemetry,
        Bullet.Vault,
        Bullet.Repo,
        {DNSCluster, query: Application.get_env(:bullet, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Bullet.PubSub},
        {Oban, Application.fetch_env!(:bullet, Oban)},
        {Bullet.RateLimit, clean_period: :timer.minutes(1)},
        Bullet.Playback.Presence,
        # Start a worker by calling: Bullet.Worker.start_link(arg)
        # {Bullet.Worker, arg},
        # Start to serve requests, typically the last entry
        BulletWeb.Endpoint
      ] ++ reaper()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Bullet.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  # Tests call Playback.reap_stale_sessions/0 directly.
  defp reaper do
    if Application.get_env(:bullet, :session_reaper, true),
      do: [Bullet.Playback.SessionReaper],
      else: []
  end

  @impl true
  def config_change(changed, _new, removed) do
    BulletWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
