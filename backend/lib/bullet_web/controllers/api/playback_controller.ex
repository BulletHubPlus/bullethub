defmodule BulletWeb.Api.PlaybackController do
  use BulletWeb, :controller

  alias Bullet.Playback
  alias BulletWeb.Api.CatalogJSON
  alias BulletWeb.ErrorResponse
  alias BulletWeb.Plugs.RateLimit

  action_fallback BulletWeb.Api.FallbackController

  # PRD §5.5: 30 req/min per account on the token endpoint (anti-enumeration).
  plug RateLimit,
       [name: "playback", limit: 30, scale: :timer.minutes(1), by: [:user]] when action == :create

  def create(conn, %{"media_id" => media_id}) when is_binary(media_id) do
    user = conn.assigns.current_user

    ctx = %{
      ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
      user_agent: conn |> get_req_header("user-agent") |> List.first()
    }

    case Playback.start_session(user, media_id, conn.assigns.current_device_id, ctx) do
      {:ok, p} ->
        conn
        |> put_status(201)
        |> json(%{
          session_id: p.session_id,
          code: p.code,
          expires: p.expires,
          source: p.source,
          watermark: p.watermark,
          resume_position: p.resume_position,
          captions: p.captions,
          media: CatalogJSON.playing(p.media),
          next_media: p.next_media && CatalogJSON.playing(p.next_media)
        })

      {:error, :email_unconfirmed} ->
        ErrorResponse.send(conn, 403, "email_unconfirmed", "Confirme seu e-mail para assistir.")

      {:error, :no_subscription} ->
        ErrorResponse.send(
          conn,
          402,
          "subscription_required",
          "Você precisa de um plano ativo para assistir."
        )

      {:error, {:stream_limit, active}} ->
        ErrorResponse.send(
          conn,
          409,
          "stream_limit",
          "Seu plano já está usando todas as telas.",
          %{active_sessions: active}
        )

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  def delete(conn, %{"id" => id}) do
    with :ok <- Playback.terminate_session(conn.assigns.current_user, id) do
      send_resp(conn, 204, "")
    end
  end

  @doc "WebVTT for the native engine (the Bunny embed loads its own copy)."
  def caption(conn, %{"id" => id}) do
    case Bullet.Catalog.get_caption(id) do
      %Bullet.Catalog.Caption{content: vtt} ->
        conn |> put_resp_content_type("text/vtt") |> send_resp(200, vtt)

      nil ->
        {:error, :not_found}
    end
  end

  @doc "HTTP fallback of the channel's `progress`, used with fetch keepalive on pagehide."
  def progress(conn, %{"media_id" => media_id, "position" => position})
      when is_number(position) do
    case Playback.save_progress(
           conn.assigns.current_user.id,
           media_id,
           position,
           conn.assigns.current_device_id
         ) do
      :ok -> send_resp(conn, 204, "")
      {:error, :invalid} -> {:error, :not_found}
    end
  end

  @kinds %{"ttff" => [:bullet, :playback, :ttff], "rebuffer" => [:bullet, :playback, :rebuffer]}

  @doc """
  QoE batch (RNF01). No PII: only the event kind, a duration and the engine.
  Emitted as :telemetry events; PromEx/Grafana consume them in Fase 4.
  """
  def telemetry(conn, %{"events" => events}) when is_list(events) do
    for %{"kind" => kind, "ms" => ms} = e <- Enum.take(events, 50),
        event = @kinds[kind],
        is_number(ms) and ms >= 0 and ms < 600_000 do
      :telemetry.execute(event, %{duration_ms: ms}, %{engine: to_string(e["engine"] || "unknown")})
    end

    send_resp(conn, 202, "")
  end
end
