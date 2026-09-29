defmodule BulletWeb.ErrorResponse do
  @moduledoc """
  Single error envelope for the SPA (PRD §10.4):
  `{"error": {"code": "stream_limit", "message": "...", "details": {}}}`.
  `code` is a stable contract; `message` is pt-BR and may change.
  """
  import Plug.Conn

  def body(code, message, details \\ %{}) do
    %{error: %{code: code, message: message, details: details}}
  end

  def send(conn, status, code, message, details \\ %{}) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body(code, message, details)))
    |> halt()
  end
end
