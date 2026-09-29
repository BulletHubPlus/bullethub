defmodule Bullet.AccountsTest do
  use Bullet.DataCase, async: true
  use Oban.Testing, repo: Bullet.Repo

  import Bullet.AccountsFixtures

  alias Bullet.Accounts
  alias Bullet.Accounts.{Device, User, UserToken}
  alias Bullet.Security.SecurityEvent
  alias Bullet.Workers.DeliverUserEmail

  describe "register_user/2" do
    test "creates the user, encrypts the CPF and enqueues confirmation" do
      attrs = valid_user_attributes(cpf: "529.982.247-25")
      assert {:ok, %User{} = user} = Accounts.register_user(attrs, &"http://x/#{&1}")

      assert user.email == attrs.email
      assert user.role == :subscriber
      assert is_nil(user.confirmed_at)
      assert_enqueued(worker: DeliverUserEmail, args: %{kind: :confirmation, user_id: user.id})

      raw =
        Repo.one!(
          from u in "users", where: u.id == type(^user.id, UUIDv7), select: u.cpf_encrypted
        )

      refute raw =~ "52998224725"
      assert Repo.get!(User, user.id).cpf_encrypted == "52998224725"
    end

    test "rejects invalid CPF, short password and bad e-mail" do
      {:error, cs} =
        Accounts.register_user(
          %{email: "x", name: "A B", password: "curta", cpf: "111.111.111-11"},
          & &1
        )

      errors = errors_on(cs)
      assert errors.cpf == ["inválido"]
      assert errors.email == ["inválido"]
      assert [_] = errors.password
    end

    test "e-mail and CPF are unique" do
      user = user_fixture(cpf: "11144477735")

      {:error, cs} =
        Accounts.register_user(valid_user_attributes(email: String.upcase(user.email)), & &1)

      assert "has already been taken" in errors_on(cs).email

      {:error, cs} = Accounts.register_user(valid_user_attributes(cpf: "111.444.777-35"), & &1)
      assert "já cadastrado" in errors_on(cs).cpf
    end
  end

  describe "confirm_user/1" do
    test "confirms with the e-mailed token, only once" do
      user = user_fixture()
      [job] = all_enqueued(worker: DeliverUserEmail)
      raw = job.args["url"] |> String.split("/") |> List.last()

      assert {:ok, confirmed} = Accounts.confirm_user(raw)
      assert confirmed.confirmed_at
      assert confirmed.id == user.id
      assert {:error, :invalid_token} = Accounts.confirm_user(raw)
    end

    test "rejects garbage" do
      assert {:error, :invalid_token} = Accounts.confirm_user("not-a-token")
    end
  end

  describe "login/4" do
    test "creates a device and a refresh token" do
      user = user_fixture()

      assert {:ok, %{user: %{id: id}, device: device, refresh_token: raw}} =
               Accounts.login(user.email, valid_password(), %{}, %{
                 user_agent: "Mozilla/5.0 (Windows NT 10.0) Chrome/130"
               })

      assert id == user.id
      assert device.name == "Chrome · Windows"
      assert is_binary(raw)
      assert {:ok, _} = Accounts.fetch_active_session(user.id, device.id)
    end

    test "wrong password logs a security event without revealing which part failed" do
      user = user_fixture()
      assert {:error, :invalid_credentials} = Accounts.login(user.email, "errada-errada-123", %{})
      assert {:error, :invalid_credentials} = Accounts.login("nobody@example.com", "x", %{})

      assert Repo.aggregate(from(e in SecurityEvent, where: e.kind == "login_failed"), :count) ==
               2
    end

    test "suspended users can't log in" do
      user = user_fixture()
      Repo.update!(Ecto.Changeset.change(user, suspended_at: DateTime.utc_now()))
      assert {:error, :suspended} = Accounts.login(user.email, valid_password(), %{})
    end
  end

  describe "refresh/2" do
    test "rotates the token" do
      %{refresh_token: r1, device: device} = session_fixture()

      assert {:ok, %{refresh_token: r2, device: %{id: same}}} = Accounts.refresh(r1)
      assert same == device.id
      assert r2 != r1
      assert {:ok, _} = Accounts.refresh(r2)
    end

    test "reusing a rotated token after the grace window revokes the device (family)" do
      %{refresh_token: r1, device: device, user: user} = session_fixture()
      {:ok, %{refresh_token: r2}} = Accounts.refresh(r1)
      age_rotated_tokens(user)

      Phoenix.PubSub.subscribe(Bullet.PubSub, "device_socket:#{device.id}")

      assert {:error, :reused} = Accounts.refresh(r1)
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
      assert Repo.get!(Device, device.id).revoked_at
      assert {:error, :invalid} = Accounts.refresh(r2)
      assert {:error, :revoked} = Accounts.fetch_active_session(user.id, device.id)
      assert Repo.get_by(SecurityEvent, kind: "refresh_reused", user_id: user.id)
    end

    test "within the grace window a rotated token is an aborted refresh, not theft" do
      %{refresh_token: r1, device: device, user: user} = session_fixture()
      {:ok, %{refresh_token: r2}} = Accounts.refresh(r1)

      # Browser navigated away before storing r2 and sends r1 again.
      assert {:ok, %{refresh_token: r3, device: %{id: same}}} = Accounts.refresh(r1)
      assert same == device.id
      assert {:error, :invalid} = Accounts.refresh(r2), "the lost successor must be invalidated"
      assert {:ok, _} = Accounts.refresh(r3)
      assert {:ok, _} = Accounts.fetch_active_session(user.id, device.id)
    end

    test "reusing an old token after the chain advanced revokes, even within the window" do
      %{refresh_token: r1, device: device, user: user} = session_fixture()
      {:ok, %{refresh_token: r2}} = Accounts.refresh(r1)
      # Legit session advances: r2 is now used, so the chain moved past r1.
      {:ok, %{refresh_token: _r3}} = Accounts.refresh(r2)

      # A thief replays r1. Even inside the 15 s window, a newer token was used,
      # so this is theft, not a retry: the whole device family is revoked.
      assert {:error, :reused} = Accounts.refresh(r1)
      assert Repo.get!(Device, device.id).revoked_at
      assert {:error, :revoked} = Accounts.fetch_active_session(user.id, device.id)
      assert Repo.get_by(SecurityEvent, kind: "refresh_reused", user_id: user.id)
    end

    test "rejects unknown and malformed tokens" do
      assert {:error, :invalid} = Accounts.refresh("%%%")

      assert {:error, :invalid} =
               Accounts.refresh(Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false))
    end
  end

  describe "revoke_device/3" do
    test "only the owner can revoke; revocation kills the session" do
      %{user: user, device: device, refresh_token: raw} = session_fixture()
      other = user_fixture()

      assert {:error, :not_found} = Accounts.revoke_device(other, device.id)
      assert :ok = Accounts.revoke_device(user, device.id)
      assert {:error, :revoked} = Accounts.fetch_active_session(user.id, device.id)
      assert {:error, :invalid} = Accounts.refresh(raw)
      assert Accounts.list_devices(user) == []
    end
  end

  describe "reset_password/2" do
    test "changes the password and signs out every device" do
      user = user_fixture()
      %{device: d1} = session_fixture(user)
      %{device: d2} = session_fixture(user)

      :ok = Accounts.request_password_reset(user.email, &"http://x/#{&1}")

      job =
        all_enqueued(worker: DeliverUserEmail)
        |> Enum.find(&(&1.args["kind"] == "reset_password"))

      raw = job.args["url"] |> String.split("/") |> List.last()

      assert {:ok, _} = Accounts.reset_password(raw, %{password: "outra-senha-longa-456"})
      assert {:error, :revoked} = Accounts.fetch_active_session(user.id, d1.id)
      assert {:error, :revoked} = Accounts.fetch_active_session(user.id, d2.id)
      assert {:ok, _} = Accounts.login(user.email, "outra-senha-longa-456", %{})

      assert {:error, :invalid_token} =
               Accounts.reset_password(raw, %{password: "mais-uma-senha-789"})
    end

    test "unknown e-mail still returns :ok" do
      assert :ok = Accounts.request_password_reset("ghost@example.com", & &1)
      refute_enqueued(worker: DeliverUserEmail)
    end
  end

  defp age_rotated_tokens(user) do
    Repo.update_all(
      from(t in UserToken, where: t.user_id == ^user.id and not is_nil(t.used_at)),
      set: [used_at: DateTime.add(DateTime.utc_now(), -60, :second)]
    )
  end

  test "idle devices leave the list and are retired by the daily prune" do
    %{user: user, device: device} = session_fixture()

    Repo.update_all(from(d in Device, where: d.id == ^device.id),
      set: [last_seen_at: DateTime.add(DateTime.utc_now(), -31, :day)]
    )

    assert Accounts.list_devices(user) == []
    Accounts.prune_expired_tokens()
    assert Repo.get!(Device, device.id).revoked_at
  end

  test "prune_expired_tokens/0 removes old tokens only" do
    %{user: user} = session_fixture()

    Repo.update_all(from(t in UserToken, where: t.user_id == ^user.id and t.context == "confirm"),
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -40, :day)]
    )

    assert {1, _} = Accounts.prune_expired_tokens()
    assert Repo.aggregate(from(t in UserToken, where: t.user_id == ^user.id), :count) == 1
  end
end
