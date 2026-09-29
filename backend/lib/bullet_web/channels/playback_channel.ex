defmodule BulletWeb.PlaybackChannel do
  @moduledoc """
  `playback:<session_id>` - one active player (PRD §10.2).

  Client → server: `heartbeat`, `progress {position}`, `event {kind}`.
  Server → client: `session_terminated {reason}`, after which the channel stops.

  Joining tracks the session in `Bullet.Playback.Presence`; leaving (tab closed,
  socket dropped, device revoked) frees the slot immediately.
  """
  use BulletWeb, :channel

  require Logger
  alias Bullet.{Playback, Security}
  alias Bullet.Playback.Presence

  @reportable_events ~w(watermark_tampered)

  intercept ["session_terminated"]

  @impl true
  def join("playback:" <> session_id, _payload, socket) do
    case Playback.join_session(session_id, socket.assigns.user_id) do
      {:ok, session} ->
        send(self(), :after_join)
        {:ok, assign(socket, session_id: session.id, media_id: session.media_id)}

      {:error, _} ->
        {:error, %{reason: "session_not_found"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _} =
      Presence.track(self(), Presence.topic(socket.assigns.user_id), socket.assigns.session_id, %{
        media_id: socket.assigns.media_id,
        device_id: socket.assigns.device_id,
        started_at: System.system_time(:second)
      })

    {:noreply, socket}
  end

  @impl true
  def handle_in("heartbeat", _payload, socket), do: {:reply, :ok, socket}

  def handle_in("progress", %{"position" => position}, socket) when is_number(position) do
    %{user_id: user_id, media_id: media_id, device_id: device_id} = socket.assigns
    Playback.save_progress(user_id, media_id, position, device_id)
    {:noreply, socket}
  end

  def handle_in("event", %{"kind" => kind} = payload, socket) when kind in @reportable_events do
    ctx = %{ip: socket.assigns[:ip], user_agent: socket.assigns[:user_agent]}

    Security.log_event(kind, socket.assigns.user_id, ctx, %{
      session_id: socket.assigns.session_id,
      detail: payload |> Map.get("detail") |> to_string() |> String.slice(0, 120)
    })

    {:noreply, socket}
  end

  def handle_in(_event, _payload, socket), do: {:noreply, socket}

  @impl true
  def handle_out("session_terminated", payload, socket) do
    push(socket, "session_terminated", payload)
    {:stop, :normal, socket}
  end

  @impl true
  def terminate(reason, socket) do
    if id = socket.assigns[:session_id] do
      Playback.end_session(id, end_reason(reason))
    end

    :ok
  end

  defp end_reason({:shutdown, :closed}), do: "closed"
  defp end_reason({:shutdown, :left}), do: "closed"
  defp end_reason(:normal), do: "terminated"
  defp end_reason(_), do: "disconnected"
end
