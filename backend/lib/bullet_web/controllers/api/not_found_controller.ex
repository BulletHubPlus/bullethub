defmodule BulletWeb.Api.NotFoundController do
  @moduledoc false
  use BulletWeb, :controller

  def show(conn, _params),
    do: BulletWeb.ErrorResponse.send(conn, 404, "not_found", "Rota não encontrada.")
end
