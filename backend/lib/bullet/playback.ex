defmodule Bullet.Playback do
  @moduledoc """
  Playback context: sessions (RF01, RF06, RF07), progress (RF03, RF13) and
  "what's next" (RF04).

  A stream counts against the plan while it is either
    * present in `Bullet.Playback.Presence` (channel joined, socket alive), or
    * freshly created and not yet joined (`@join_grace_seconds`).

  Liveness comes from Presence, not from DB heartbeats, so 10k viewers don't
  turn into thousands of writes per second. The limit check runs under a
  per-user advisory lock so two simultaneous requests can't both take the
  last slot.
  """

  import Ecto.Query
  require Logger

  alias Bullet.Accounts.User
  alias Bullet.{Billing, Catalog, Repo, Security}
  alias Bullet.Catalog.Media
  alias Bullet.Media.Provider
  alias Bullet.Playback.{PlaybackSession, Presence, WatchProgress}
  alias Bullet.Security.PlaybackToken
  alias Phoenix.Channel.Server, as: ChannelServer

  @join_grace_seconds 30
  @code_alphabet ~c"23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
  @completed_ratio 0.95
  @min_resume_seconds 30

  ## Sessions

  @type start_error ::
          :email_unconfirmed
          | :no_subscription
          | :not_found
          | {:stream_limit, [map()]}

  @doc """
  Authorizes and opens a stream. Returns everything the player needs: the
  signed source, the watermark and where to resume.
  """
  @spec start_session(User.t(), String.t(), String.t() | nil, map()) ::
          {:ok, map()} | {:error, start_error()}
  def start_session(%User{} = user, media_id, device_id, ctx \\ %{}) do
    with :ok <- ensure_confirmed(user),
         %{plan: plan} <- Billing.access(user) || {:error, :no_subscription},
         %Media{} = media <- Catalog.get_playable_media(media_id) || {:error, :not_found},
         {:ok, session} <- open_session(user, media, device_id, plan.max_streams, ctx) do
      {:ok, build_payload(user, media, session)}
    else
      {:error, {:stream_limit, active}} = error ->
        Security.log_event("session_limit_hit", user.id, ctx, %{active: length(active)})
        error

      error ->
        error
    end
  end

  defp ensure_confirmed(%User{confirmed_at: nil}), do: {:error, :email_unconfirmed}
  defp ensure_confirmed(_), do: :ok

  defp open_session(user, media, device_id, max_streams, ctx) do
    Repo.transaction(fn ->
      # Serializes concurrent starts of the same account for this transaction.
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["streams:" <> user.id])

      active = active_sessions(user.id)

      if length(active) >= max_streams do
        Repo.rollback({:stream_limit, Enum.map(active, &session_summary/1)})
      else
        insert_session(user, media, device_id, ctx)
      end
    end)
  end

  # 32^6 ≈ 1e9 codes; a collision aborts the transaction (Postgres can't retry
  # inside it) and surfaces as an error - acceptable at that probability.
  defp insert_session(user, media, device_id, ctx) do
    %PlaybackSession{
      user_id: user.id,
      media_id: media.id,
      device_id: device_id,
      code: random_code(),
      ip: ctx[:ip],
      started_at: DateTime.utc_now()
    }
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.unique_constraint(:code)
    |> Repo.insert()
    |> case do
      {:ok, session} -> session
      {:error, cs} -> Repo.rollback(cs)
    end
  end

  defp random_code do
    for _ <- 1..6, into: "", do: <<Enum.random(@code_alphabet)>>
  end

  @doc "Open sessions that currently hold a slot (see moduledoc)."
  def active_sessions(user_id) do
    present = Presence.session_ids(user_id)
    grace = DateTime.add(DateTime.utc_now(), -@join_grace_seconds, :second)

    Repo.all(
      from s in PlaybackSession,
        where: s.user_id == ^user_id and is_nil(s.ended_at),
        order_by: [asc: s.started_at],
        preload: [:device, media: :collection]
    )
    |> Enum.filter(fn s ->
      MapSet.member?(present, s.id) or
        (is_nil(s.joined_at) and DateTime.after?(s.started_at, grace))
    end)
  end

  defp session_summary(%PlaybackSession{} = s) do
    %{
      id: s.id,
      device_name: s.device && s.device.name,
      media_title: media_title(s.media),
      started_at: s.started_at
    }
  end

  defp media_title(nil), do: nil
  defp media_title(%Media{collection: %{title: c}, title: t}), do: "#{c} · #{t}"
  defp media_title(%Media{title: t}), do: t

  defp build_payload(user, media, session) do
    expires = PlaybackToken.expires_at(media.asset.duration_seconds, System.os_time(:second))

    %{
      session_id: session.id,
      code: session.code,
      expires: expires,
      source: Provider.playback_source(media.asset.bunny_video_id, expires),
      watermark: %{text: "#{mask_email(user.email)} · #{session.code}"},
      resume_position: resume_position(user.id, media.id),
      captions: Enum.map(Catalog.list_captions(media), &Map.take(&1, [:id, :srclang, :label])),
      media: media,
      next_media: Catalog.next_media(media)
    }
  end

  @doc "`carlos@gmail.com` → `ca***@gmail.com` (RF06: never the CPF, never the full e-mail)."
  def mask_email(email) do
    case String.split(email, "@", parts: 2) do
      [local, domain] -> String.slice(local, 0, 2) <> "***@" <> domain
      _ -> "***"
    end
  end

  @doc "Channel join: marks the session live. Only the owner, only while open."
  def join_session(session_id, user_id) do
    with {:ok, id} <- Ecto.UUID.cast(session_id),
         %PlaybackSession{ended_at: nil} = s <-
           Repo.get_by(PlaybackSession, id: id, user_id: user_id) do
      s |> Ecto.Changeset.change(joined_at: s.joined_at || DateTime.utc_now()) |> Repo.update()
    else
      _ -> {:error, :not_found}
    end
  end

  def end_session(session_id, reason) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(s in PlaybackSession, where: s.id == ^session_id and is_nil(s.ended_at)),
      set: [ended_at: now, last_heartbeat_at: now, end_reason: reason, updated_at: now]
    )

    :ok
  end

  @doc "RF07: end one of the account's own streams from another device."
  @spec terminate_session(User.t(), String.t()) :: :ok | {:error, :not_found}
  def terminate_session(%User{id: user_id}, session_id) do
    with {:ok, id} <- Ecto.UUID.cast(session_id),
         %PlaybackSession{ended_at: nil} <- Repo.get_by(PlaybackSession, id: id, user_id: user_id) do
      end_session(id, "terminated_by_user")
      broadcast("playback:#{id}", "session_terminated", %{reason: "terminated_by_user"})
      :ok
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Closes sessions that lost their stream without a clean `terminate/2` (node
  crash, never joined). Run by `Bullet.Playback.SessionReaper`.
  """
  def reap_stale_sessions do
    joined_cutoff = DateTime.add(DateTime.utc_now(), -45, :second)
    unjoined_cutoff = DateTime.add(DateTime.utc_now(), -@join_grace_seconds * 2, :second)

    Repo.all(
      from s in PlaybackSession,
        where: is_nil(s.ended_at),
        where:
          (not is_nil(s.joined_at) and s.joined_at < ^joined_cutoff) or
            (is_nil(s.joined_at) and s.started_at < ^unjoined_cutoff),
        select: {s.id, s.user_id}
    )
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Enum.flat_map(fn {user_id, ids} ->
      present = Presence.session_ids(user_id)
      Enum.reject(ids, &MapSet.member?(present, &1))
    end)
    |> tap(fn stale -> Enum.each(stale, &end_session(&1, "timeout")) end)
  end

  ## Progress

  @doc """
  Upserts the position (RF03) and tells the account's other devices, which
  update their UI without seeking (PRD §11).
  """
  def save_progress(user_id, media_id, position, device_id \\ nil) do
    with %Media{asset: %{duration_seconds: duration}} <- Catalog.get_playable_media(media_id),
         position when is_number(position) and position >= 0 <- position do
      position = position |> trunc() |> min(duration || trunc(position))

      completed =
        is_integer(duration) and duration > 0 and position >= duration * @completed_ratio

      now = DateTime.utc_now()

      Repo.insert!(
        %WatchProgress{
          user_id: user_id,
          media_id: media_id,
          position_seconds: position,
          completed: completed
        },
        on_conflict: [set: [position_seconds: position, completed: completed, updated_at: now]],
        conflict_target: [:user_id, :media_id]
      )

      broadcast("user:#{user_id}", "progress_updated", %{
        media_id: media_id,
        position: position,
        completed: completed,
        device_id: device_id
      })

      :ok
    else
      _ -> {:error, :invalid}
    end
  end

  def resume_position(user_id, media_id) do
    case Repo.get_by(WatchProgress, user_id: user_id, media_id: media_id) do
      %WatchProgress{completed: false, position_seconds: p} when p >= @min_resume_seconds -> p
      _ -> 0
    end
  end

  @doc "`media_id => %{position, completed}` for the given media (collection page)."
  def progress_map(user_id, media_ids) do
    Repo.all(
      from p in WatchProgress,
        where: p.user_id == ^user_id and p.media_id in ^media_ids,
        select: {p.media_id, %{position: p.position_seconds, completed: p.completed}}
    )
    |> Map.new()
  end

  @doc """
  "Continuar assistindo" (RF13): unfinished, past the first 30 s, newest first.
  One indexed query on (user_id, updated_at desc); no materialized table.
  """
  def continue_watching(user_id, limit \\ 20) do
    Repo.all(
      from p in WatchProgress,
        join: m in assoc(p, :media),
        join: a in assoc(m, :asset),
        left_join: c in assoc(m, :collection),
        where:
          p.user_id == ^user_id and not p.completed and p.position_seconds >= @min_resume_seconds,
        where: not is_nil(m.published_at) and a.status == :ready,
        order_by: [desc: p.updated_at],
        limit: ^limit,
        preload: [media: {m, asset: a, collection: c}]
    )
  end

  # Channel.Server's dispatcher fastlanes the push straight to the sockets. A
  # plain PubSub.broadcast would land in each channel's handle_out/3 instead,
  # crashing channels that don't intercept the event.
  defp broadcast(topic, event, payload) do
    ChannelServer.broadcast(Bullet.PubSub, topic, event, payload)
  end
end
