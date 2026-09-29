defmodule BulletWeb.Api.ListController do
  @moduledoc "Minha lista: `PUT/DELETE /api/me/list/:kind/:id` with kind `collection` or `movie`."
  use BulletWeb, :controller

  alias Bullet.Library

  action_fallback BulletWeb.Api.FallbackController

  @kinds %{"collection" => :collection, "movie" => :movie}

  def add(conn, %{"kind" => kind, "id" => id}) do
    with {:ok, kind} <- Map.fetch(@kinds, kind) |> ok_or_not_found(),
         :ok <- Library.add(conn.assigns.current_user.id, kind, id) do
      send_resp(conn, 204, "")
    end
  end

  def remove(conn, %{"kind" => kind, "id" => id}) do
    with {:ok, kind} <- Map.fetch(@kinds, kind) |> ok_or_not_found(),
         :ok <- Library.remove(conn.assigns.current_user.id, kind, id) do
      send_resp(conn, 204, "")
    end
  end

  defp ok_or_not_found({:ok, _} = ok), do: ok
  defp ok_or_not_found(:error), do: {:error, :not_found}
end
