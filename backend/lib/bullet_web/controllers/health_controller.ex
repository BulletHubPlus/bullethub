defmodule BulletWeb.HealthController do
  @moduledoc "Liveness for Traefik/Coolify and the external uptime check (RNF06)."
  use BulletWeb, :controller

  alias Ecto.Adapters.SQL

  def show(conn, _params) do
    checks = %{database: database_ok?(), jobs: oban_ok?()}
    status = if Enum.all?(Map.values(checks)), do: 200, else: 503

    conn
    |> put_status(status)
    |> json(%{status: if(status == 200, do: "ok", else: "degraded"), checks: checks})
  end

  defp database_ok? do
    match?({:ok, _}, SQL.query(Bullet.Repo, "SELECT 1", [], timeout: 2_000))
  rescue
    _ -> false
  end

  defp oban_ok? do
    case Oban.config() do
      # Test mode runs no queues; nothing to check.
      %{testing: mode} when mode in [:manual, :inline] -> true
      _ -> match?(%{paused: false}, Oban.check_queue(queue: :default))
    end
  catch
    _, _ -> false
  end
end
