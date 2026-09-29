defmodule Bullet.Accounts do
  @moduledoc """
  Accounts context (RF11): registration, e-mail confirmation, password reset,
  device-bound sessions with rotating refresh tokens, and device revocation.

  Session model:

    * each login creates a `Device`;
    * the device holds exactly one live refresh token (`context: "refresh"`);
    * rotating marks the old token `used_at` and issues a new one;
    * presenting a token that was already rotated is treated as theft and
      revokes the whole device ("family"), per PRD §10.1.

  Short-lived access tokens are minted by the web layer (`BulletWeb.AccessToken`);
  this context only answers whether a `{user_id, device_id}` pair is still live.
  """

  import Ecto.Query

  alias Bullet.Accounts.{Device, User, UserNotifier, UserToken}
  alias Bullet.{Repo, Security}
  alias Phoenix.Channel.Server, as: ChannelServer

  @confirm_validity_seconds 7 * 24 * 60 * 60
  @refresh_reuse_grace_seconds 15
  @reset_validity_seconds 60 * 60

  @type ctx :: %{optional(:ip) => String.t() | nil, optional(:user_agent) => String.t() | nil}
  @type session :: %{user: User.t(), device: Device.t(), refresh_token: String.t()}

  ## Users

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(String.trim(email)))
  end

  @doc """
  Registers a user and enqueues the confirmation e-mail in the same transaction
  (outbox), so a user never exists without their confirmation job.
  """
  @spec register_user(map(), (String.t() -> String.t())) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_user(attrs, confirm_url_fun) do
    Repo.transaction(fn ->
      with {:ok, user} <- %User{} |> User.registration_changeset(attrs) |> Repo.insert(),
           {:ok, _job} <- enqueue_confirmation(user, confirm_url_fun) do
        user
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def resend_confirmation(%User{confirmed_at: nil} = user, confirm_url_fun) do
    enqueue_confirmation(user, confirm_url_fun)
  end

  def resend_confirmation(%User{}, _), do: {:error, :already_confirmed}

  defp enqueue_confirmation(user, confirm_url_fun) do
    {raw, token} = UserToken.build(user, "confirm", sent_to: user.email)
    Repo.insert!(token)
    UserNotifier.enqueue(:confirmation, user, confirm_url_fun.(raw))
  end

  @spec confirm_user(String.t()) :: {:ok, User.t()} | {:error, :invalid_token}
  def confirm_user(raw) do
    with {:ok, query} <- UserToken.by_raw_query(raw, "confirm", @confirm_validity_seconds),
         %UserToken{user_id: user_id} = token <- Repo.one(query),
         %User{} = user <- Repo.get(User, user_id),
         true <- token.sent_to == user.email do
      Repo.transaction(fn ->
        Repo.delete_all(UserToken.by_user_and_contexts_query(user.id, ["confirm"]))
        Repo.update!(User.confirm_changeset(user))
      end)
    else
      _ -> {:error, :invalid_token}
    end
  end

  @doc "Always returns `:ok` so the endpoint can't be used to enumerate e-mails."
  def request_password_reset(email, reset_url_fun) do
    with %User{suspended_at: nil} = user <- get_user_by_email(email) do
      {raw, token} = UserToken.build(user, "reset", sent_to: user.email)
      Repo.insert!(token)
      UserNotifier.enqueue(:reset_password, user, reset_url_fun.(raw))
    end

    :ok
  end

  @doc "Resets the password and signs the user out of every device."
  @spec reset_password(String.t(), map()) ::
          {:ok, User.t()} | {:error, :invalid_token | Ecto.Changeset.t()}
  def reset_password(raw, attrs) do
    with {:ok, query} <- UserToken.by_raw_query(raw, "reset", @reset_validity_seconds),
         %UserToken{user_id: user_id} <- Repo.one(query),
         %User{} = user <- Repo.get(User, user_id),
         {:ok, {user, revoked}} <- Repo.transaction(fn -> do_reset_password(user, attrs) end) do
      Enum.each(revoked, &broadcast_device_revoked(user.id, &1))
      {:ok, user}
    else
      {:error, %Ecto.Changeset{}} = error -> error
      _ -> {:error, :invalid_token}
    end
  end

  defp do_reset_password(user, attrs) do
    case Repo.update(User.password_changeset(user, attrs)) do
      {:ok, user} ->
        Repo.delete_all(UserToken.by_user_and_contexts_query(user.id, ["reset", "refresh"]))
        {user, revoke_all_devices_in_tx(user.id)}

      {:error, cs} ->
        Repo.rollback(cs)
    end
  end

  ## Sessions

  @doc "Checks credentials, creates a device and its first refresh token."
  @spec login(String.t(), String.t(), map(), ctx()) ::
          {:ok, session()} | {:error, :invalid_credentials | :suspended}
  def login(email, password, device_attrs, ctx \\ %{}) do
    user = get_user_by_email(email || "")

    cond do
      not User.valid_password?(user, password || "") ->
        Security.log_event("login_failed", user && user.id, ctx)
        {:error, :invalid_credentials}

      user.suspended_at ->
        {:error, :suspended}

      true ->
        Repo.transaction(fn ->
          device =
            %Device{user_id: user.id, last_seen_at: DateTime.utc_now()}
            |> Device.create_changeset(%{
              name: device_attrs[:name] || default_device_name(ctx[:user_agent]),
              user_agent: ctx[:user_agent]
            })
            |> Repo.insert!()

          %{user: user, device: device, refresh_token: issue_refresh_token(user, device)}
        end)
    end
  end

  @doc """
  Rotates a refresh token. Reusing a rotated token revokes the device.
  """
  @spec refresh(String.t(), ctx()) :: {:ok, session()} | {:error, :invalid | :reused}
  def refresh(raw, ctx \\ %{}) do
    validity = Application.fetch_env!(:bullet, :auth)[:refresh_token_ttl_days] * 86_400

    case UserToken.by_raw_query(raw, "refresh", validity) do
      {:ok, query} -> query |> rotate_in_tx() |> after_rotation(ctx)
      :error -> {:error, :invalid}
    end
  end

  defp rotate_in_tx(query) do
    {:ok, result} =
      Repo.transaction(fn ->
        query
        |> lock("FOR UPDATE")
        |> preload([:user, :device])
        |> Repo.one()
        |> rotate()
      end)

    result
  end

  defp after_rotation({:rotated, session}, _ctx), do: {:ok, session}
  defp after_rotation(:invalid, _ctx), do: {:error, :invalid}

  defp after_rotation({:reused, token}, ctx) do
    Security.log_event("refresh_reused", token.user_id, ctx, %{device_id: token.device_id})
    broadcast_device_revoked(token.user_id, token.device_id)
    {:error, :reused}
  end

  defp rotate(nil), do: :invalid

  # A rotated token presented again is only tolerated as a benign retry (a reload
  # or closed tab that aborted the refresh response, so the browser never stored
  # the successor cookie) when BOTH hold: it happened within the grace window AND
  # the chain has not advanced past it (no newer refresh token was already used).
  # Anything else - an old token replayed after the session moved on - is treated
  # as theft and revokes the whole device family (PRD §10.1, OAuth rotation).
  defp rotate(%UserToken{used_at: used_at} = token) when not is_nil(used_at) do
    if live?(token) and within_reuse_grace?(used_at) and newest_used?(token) do
      Repo.delete_all(
        from t in UserToken.by_device_query(token.device_id), where: is_nil(t.used_at)
      )

      issue_rotation(token)
    else
      revoke_device_in_tx(token.device_id)
      {:reused, token}
    end
  end

  defp rotate(%UserToken{} = token) do
    if live?(token) do
      Repo.update!(Ecto.Changeset.change(token, used_at: DateTime.utc_now()))
      issue_rotation(token)
    else
      :invalid
    end
  end

  defp live?(%UserToken{device: %Device{revoked_at: nil}, user: %User{suspended_at: nil}}),
    do: true

  defp live?(_), do: false

  defp within_reuse_grace?(used_at),
    do: DateTime.diff(DateTime.utc_now(), used_at, :second) <= @refresh_reuse_grace_seconds

  # True only if no refresh token for this device was used more recently: the
  # legitimate chain is still at this link, so a concurrent retry is plausible.
  defp newest_used?(%UserToken{device_id: device_id, used_at: used_at}) do
    not Repo.exists?(
      from t in UserToken,
        where:
          t.device_id == ^device_id and t.context == "refresh" and
            not is_nil(t.used_at) and t.used_at > ^used_at
    )
  end

  defp issue_rotation(%UserToken{user: user, device: device}) do
    device = Repo.update!(Ecto.Changeset.change(device, last_seen_at: DateTime.utc_now()))
    {:rotated, %{user: user, device: device, refresh_token: issue_refresh_token(user, device)}}
  end

  @doc "Logout: revokes the device that owns this refresh token."
  def logout(raw) do
    validity = Application.fetch_env!(:bullet, :auth)[:refresh_token_ttl_days] * 86_400

    with {:ok, query} <- UserToken.by_raw_query(raw, "refresh", validity),
         %UserToken{device_id: device_id, user_id: user_id} <- Repo.one(query) do
      revoke_device_in_tx(device_id)
      broadcast_device_revoked(user_id, device_id)
    end

    :ok
  end

  @doc """
  Resolves the user behind an access token's `{user_id, device_id}`. Called
  on every API request and socket connect, so revocation is effective at once.
  """
  @spec fetch_active_session(String.t(), String.t()) :: {:ok, User.t()} | {:error, :revoked}
  def fetch_active_session(user_id, device_id) do
    query =
      from u in User,
        join: d in Device,
        on: d.user_id == u.id,
        where: u.id == ^user_id and d.id == ^device_id,
        where: is_nil(d.revoked_at) and is_nil(u.suspended_at),
        select: u

    case Repo.one(query) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :revoked}
    end
  end

  ## LGPD & suspension - see Bullet.Accounts.Privacy

  defdelegate export_user_data(user), to: Bullet.Accounts.Privacy
  defdelegate erase_user(user), to: Bullet.Accounts.Privacy
  defdelegate suspend_user(user, by, reason \\ ""), to: Bullet.Accounts.Privacy
  defdelegate unsuspend_user(user, by), to: Bullet.Accounts.Privacy

  ## Admin sessions (admin.bullethub.app)

  @staff_roles [:owner, :editor, :support]
  @admin_session_validity_seconds 12 * 60 * 60

  def staff_roles, do: @staff_roles

  @doc "Password login for the admin panel. Only staff roles; same error for everything else."
  @spec admin_login(String.t(), String.t(), ctx()) ::
          {:ok, User.t(), String.t()} | {:error, :invalid_credentials}
  def admin_login(email, password, ctx \\ %{}) do
    user = get_user_by_email(email || "")

    if User.valid_password?(user, password || "") and user.role in @staff_roles and
         is_nil(user.suspended_at) do
      {raw, token} = UserToken.build(user, "admin_session")
      Repo.insert!(token)
      {:ok, user, raw}
    else
      Security.log_event("login_failed", user && user.id, ctx, %{panel: "admin"})
      {:error, :invalid_credentials}
    end
  end

  def get_staff_by_admin_token(raw) when is_binary(raw) do
    case UserToken.by_raw_query(raw, "admin_session", @admin_session_validity_seconds) do
      {:ok, query} ->
        Repo.one(
          from t in query,
            join: u in assoc(t, :user),
            where: u.role in ^@staff_roles and is_nil(u.suspended_at),
            select: u
        )

      :error ->
        nil
    end
  end

  def get_staff_by_admin_token(_), do: nil

  def delete_admin_token(raw) when is_binary(raw) do
    with {:ok, query} <-
           UserToken.by_raw_query(raw, "admin_session", @admin_session_validity_seconds) do
      Repo.delete_all(query)
    end

    :ok
  end

  def delete_admin_token(_), do: :ok

  @doc "Grants a role. Used from a release shell: `bin/bullet eval 'Bullet.Release.promote(...)'`."
  def set_role(%User{} = user, role) when role in [:subscriber | @staff_roles] do
    user |> Ecto.Changeset.change(role: role) |> Repo.update()
  end

  ## Devices

  @doc "Devices that can still refresh: not revoked and seen within the refresh validity."
  def list_devices(%User{id: user_id}) do
    days = Application.fetch_env!(:bullet, :auth)[:refresh_token_ttl_days]

    Repo.all(
      from d in Device,
        where: d.user_id == ^user_id and is_nil(d.revoked_at),
        where: d.last_seen_at > ago(^days, "day"),
        order_by: [desc: d.last_seen_at]
    )
  end

  @spec revoke_device(User.t(), String.t(), ctx()) :: :ok | {:error, :not_found}
  def revoke_device(%User{id: user_id}, device_id, ctx \\ %{}) do
    case Repo.get_by(Device, id: device_id, user_id: user_id) do
      %Device{revoked_at: nil} ->
        revoke_device_in_tx(device_id)
        Security.log_event("device_revoked", user_id, ctx, %{device_id: device_id})
        broadcast_device_revoked(user_id, device_id)
        :ok

      _ ->
        {:error, :not_found}
    end
  end

  defp revoke_device_in_tx(device_id) do
    now = DateTime.utc_now()

    Repo.update_all(from(d in Device, where: d.id == ^device_id and is_nil(d.revoked_at)),
      set: [revoked_at: now]
    )

    Repo.delete_all(from(t in UserToken.by_device_query(device_id), where: is_nil(t.used_at)))
  end

  defp revoke_all_devices_in_tx(user_id) do
    {_, ids} =
      Repo.update_all(
        from(d in Device, where: d.user_id == ^user_id and is_nil(d.revoked_at), select: d.id),
        set: [revoked_at: DateTime.utc_now()]
      )

    ids
  end

  @doc """
  Drops every socket of the device (`id/1` in `BulletWeb.UserSocket`) and tells
  the account's other devices to refresh their list. RF11: ≤10 s.
  """
  def broadcast_device_revoked(user_id, device_id) do
    broadcast("device_socket:#{device_id}", "disconnect", %{})
    broadcast("user:#{user_id}", "device_revoked", %{device_id: device_id})
  end

  # Channel.Server's dispatcher fastlanes the push straight to the sockets. A
  # plain PubSub.broadcast would land in each channel's handle_out/3 instead,
  # crashing channels that don't intercept the event.
  defp broadcast(topic, event, payload) do
    ChannelServer.broadcast(Bullet.PubSub, topic, event, payload)
  end

  @doc """
  Deletes tokens past their validity window and retires devices idle for as
  long (their refresh token is dead anyway), so device lists don't grow forever.
  """
  def prune_expired_tokens do
    days = Application.fetch_env!(:bullet, :auth)[:refresh_token_ttl_days]

    Repo.update_all(
      from(d in Device, where: is_nil(d.revoked_at) and d.last_seen_at < ago(^days, "day")),
      set: [revoked_at: DateTime.utc_now()]
    )

    Repo.delete_all(
      from t in UserToken,
        where:
          t.inserted_at < ago(^days, "day") or
            (t.context == "reset" and t.inserted_at < ago(1, "day"))
    )
  end

  defp issue_refresh_token(user, device) do
    {raw, token} = UserToken.build(user, "refresh", device_id: device.id)
    Repo.insert!(token)
    raw
  end

  @browsers [
    {"Edg/", "Edge"},
    {"Firefox/", "Firefox"},
    {"Chrome/", "Chrome"},
    {"Safari/", "Safari"}
  ]
  @systems [
    {"iPhone", "iOS"},
    {"iPad", "iOS"},
    {"Android", "Android"},
    {"Windows", "Windows"},
    {"Mac OS X", "macOS"},
    {"Linux", "Linux"}
  ]

  defp default_device_name(nil), do: "Navegador"

  defp default_device_name(ua) do
    [detect(ua, @browsers) || "Navegador", detect(ua, @systems)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  # Order matters: Edge UAs also contain "Chrome/", Chrome UAs contain "Safari/".
  defp detect(ua, table),
    do: Enum.find_value(table, fn {needle, label} -> if ua =~ needle, do: label end)
end
