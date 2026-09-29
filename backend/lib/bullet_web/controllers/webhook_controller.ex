defmodule BulletWeb.WebhookController do
  use BulletWeb, :controller

  require Logger
  alias Bullet.Ingest
  alias BulletWeb.{CacheBodyReader, ErrorResponse}

  @doc "Bunny Stream encoding events. Always 200 for valid, even duplicates (idempotent)."
  def bunny(conn, _params) do
    signature = conn |> get_req_header("x-bunnystream-signature") |> List.first()

    case Ingest.accept_bunny_webhook(CacheBodyReader.raw_body(conn), signature) do
      {:ok, _} ->
        json(conn, %{ok: true})

      {:error, :invalid_signature} ->
        Logger.warning("webhook: invalid Bunny signature from #{:inet.ntoa(conn.remote_ip)}")
        ErrorResponse.send(conn, 401, "invalid_signature", "Assinatura inválida.")

      {:error, :bad_payload} ->
        ErrorResponse.send(conn, 400, "bad_payload", "Payload inválido.")
    end
  end
end
