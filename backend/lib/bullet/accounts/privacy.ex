defmodule Bullet.Accounts.Privacy do
  @moduledoc """
  LGPD data-subject rights (PRD §12) and account suspension (runbook 3).

  * `export_user_data/1` - everything we hold about the person, as JSON-ready maps.
  * `erase_user/1` - anonymizes in place. The row stays because fiscal data
    (CPF, subscriptions) must be kept for 5 years; everything else about
    behaviour (progress, devices, IPs, stream history) is deleted or unlinked.
  * `purge_expired/0` - retention: IP/UA kept 30 days on streams, security
    events 90 days, processed webhooks 90 days.

  Not legal advice: the DPO validates the retention table (see docs/lgpd/RIPD.md).
  """

  import Ecto.Query

  alias Bullet.Accounts
  alias Bullet.Accounts.{Device, User, UserToken}
  alias Bullet.Billing.Subscription
  alias Bullet.Ingest.WebhookEvent
  alias Bullet.Playback.{PlaybackSession, WatchProgress}
  alias Bullet.Repo
  alias Bullet.Security
  alias Bullet.Security.SecurityEvent

  @stream_ip_retention_days 30
  @security_event_retention_days 90
  @webhook_retention_days 90

  ## Export

  @spec export_user_data(User.t()) :: map()
  def export_user_data(%User{id: id} = user) do
    %{
      exported_at: DateTime.utc_now(),
      account: %{
        id: user.id,
        name: user.name,
        email: user.email,
        cpf: user.cpf_encrypted,
        role: user.role,
        created_at: user.inserted_at,
        confirmed_at: user.confirmed_at
      },
      devices:
        Repo.all(from d in Device, where: d.user_id == ^id, order_by: d.inserted_at)
        |> Enum.map(
          &Map.take(&1, [:id, :name, :user_agent, :last_seen_at, :revoked_at, :inserted_at])
        ),
      subscriptions:
        Repo.all(
          from s in Subscription, where: s.user_id == ^id, preload: :plan, order_by: s.inserted_at
        )
        |> Enum.map(fn s ->
          %{
            plan: s.plan.name,
            status: s.status,
            gateway: s.gateway,
            current_period_end: s.current_period_end,
            created_at: s.inserted_at
          }
        end),
      watch_progress:
        Repo.all(
          from p in WatchProgress,
            join: m in assoc(p, :media),
            where: p.user_id == ^id,
            order_by: [desc: p.updated_at],
            select: %{
              media_id: m.id,
              title: m.title,
              position_seconds: p.position_seconds,
              completed: p.completed,
              updated_at: p.updated_at
            }
        ),
      playback_sessions:
        Repo.all(
          from s in PlaybackSession,
            where: s.user_id == ^id,
            order_by: [desc: s.started_at],
            select: map(s, [:id, :media_id, :code, :ip, :started_at, :ended_at, :end_reason])
        ),
      security_events:
        Repo.all(
          from e in SecurityEvent,
            where: e.user_id == ^id,
            order_by: [desc: e.inserted_at],
            select: map(e, [:kind, :ip, :user_agent, :metadata, :inserted_at])
        )
    }
  end

  ## Erasure

  @doc """
  Irreversible. Keeps: the row id, `cpf_encrypted`/`cpf_hash` and subscriptions
  (fiscal obligation). Removes: name, e-mail, password, devices and tokens,
  watch progress. Unlinks: stream history and security events.
  """
  @spec erase_user(User.t()) :: {:ok, User.t()}
  def erase_user(%User{id: id} = user) do
    device_ids =
      Repo.all(from d in Device, where: d.user_id == ^id and is_nil(d.revoked_at), select: d.id)

    now = DateTime.utc_now()

    {:ok, user} =
      Repo.transaction(fn ->
        Repo.delete_all(from p in WatchProgress, where: p.user_id == ^id)
        Repo.delete_all(from t in UserToken, where: t.user_id == ^id)
        Repo.delete_all(from d in Device, where: d.user_id == ^id)

        Repo.update_all(from(s in PlaybackSession, where: s.user_id == ^id),
          set: [
            user_id: nil,
            device_id: nil,
            ip: nil,
            ended_at: now,
            end_reason: "account_erased"
          ]
        )

        Repo.update_all(from(e in SecurityEvent, where: e.user_id == ^id),
          set: [user_id: nil, ip: nil, user_agent: nil]
        )

        Repo.update_all(
          from(s in Subscription, where: s.user_id == ^id and s.status != :canceled),
          set: [status: :canceled, updated_at: now]
        )

        user
        |> Ecto.Changeset.change(
          email: "apagado+#{id}@invalid.bullethub",
          name: "Conta removida",
          # Unusable: no password hashes to a random 64-byte value.
          password_hash: Argon2.hash_pwd_salt(Base.encode64(:crypto.strong_rand_bytes(48))),
          role: :subscriber,
          deleted_at: now,
          suspended_at: now
        )
        |> Repo.update!()
      end)

    Enum.each(device_ids, &Accounts.broadcast_device_revoked(id, &1))
    {:ok, user}
  end

  ## Suspension (support / owner)

  @spec suspend_user(User.t(), User.t(), String.t()) :: {:ok, User.t()}
  def suspend_user(%User{id: id} = user, %User{} = by, reason \\ "") do
    device_ids =
      Repo.all(from d in Device, where: d.user_id == ^id and is_nil(d.revoked_at), select: d.id)

    now = DateTime.utc_now()

    {:ok, user} =
      Repo.transaction(fn ->
        Repo.update_all(from(d in Device, where: d.id in ^device_ids), set: [revoked_at: now])

        Repo.delete_all(
          from t in UserToken,
            where: t.user_id == ^id and t.context in ["refresh", "admin_session"]
        )

        Repo.update!(Ecto.Changeset.change(user, suspended_at: now))
      end)

    Security.log_event("account_suspended", id, %{}, %{
      by: by.id,
      reason: String.slice(reason, 0, 200)
    })

    Enum.each(device_ids, &Accounts.broadcast_device_revoked(id, &1))
    {:ok, user}
  end

  def unsuspend_user(%User{deleted_at: nil} = user, %User{} = by) do
    Security.log_event("account_unsuspended", user.id, %{}, %{by: by.id})
    user |> Ecto.Changeset.change(suspended_at: nil) |> Repo.update()
  end

  def unsuspend_user(%User{}, _by), do: {:error, :erased}

  ## Retention

  @doc "Daily. Returns how many rows each rule touched."
  def purge_expired do
    {ips, _} =
      Repo.update_all(
        from(s in PlaybackSession,
          where: not is_nil(s.ip) and s.started_at < ago(@stream_ip_retention_days, "day")
        ),
        set: [ip: nil]
      )

    {events, _} =
      Repo.delete_all(
        from e in SecurityEvent, where: e.inserted_at < ago(@security_event_retention_days, "day")
      )

    {webhooks, _} =
      Repo.delete_all(
        from w in WebhookEvent,
          where:
            not is_nil(w.processed_at) and w.inserted_at < ago(@webhook_retention_days, "day")
      )

    %{stream_ips_cleared: ips, security_events_deleted: events, webhook_events_deleted: webhooks}
  end
end
