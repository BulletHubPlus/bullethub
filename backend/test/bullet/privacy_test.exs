defmodule Bullet.PrivacyTest do
  use Bullet.DataCase, async: true

  import Bullet.AccountsFixtures
  import Bullet.CatalogFixtures

  alias Bullet.{Accounts, Playback, Support}
  alias Bullet.Accounts.{Device, User, UserToken}
  alias Bullet.Accounts.Privacy
  alias Bullet.Billing.Subscription
  alias Bullet.Playback.{PlaybackSession, WatchProgress}
  alias Bullet.Security.SecurityEvent

  defp watched_subscriber do
    user = subscriber_fixture("padrao", %{cpf: "529.982.247-25"})
    {:ok, %{device: device}} = Accounts.login(user.email, valid_password(), %{})
    movie = published_movie_fixture()
    {:ok, p} = Playback.start_session(user, movie.id, device.id, %{ip: "200.1.2.3"})
    :ok = Playback.save_progress(user.id, movie.id, 60)
    %{user: Repo.reload!(user), device: device, movie: movie, session: p}
  end

  test "export_user_data has every category, CPF in clear for its owner" do
    %{user: user, session: p} = watched_subscriber()
    data = Accounts.export_user_data(user)

    assert data.account.email == user.email
    assert data.account.cpf == "52998224725"
    assert [%{status: :active, plan: "Padrão"}] = data.subscriptions
    assert [%{position_seconds: 60}] = data.watch_progress
    assert [%{code: code, ip: "200.1.2.3"}] = data.playback_sessions
    assert code == p.code
    assert [_ | _] = data.devices
    assert Jason.encode!(data)
  end

  test "erase_user anonymizes, keeps fiscal data, unlinks streams and kills sessions" do
    %{user: user, device: device, session: p} = watched_subscriber()
    email = user.email
    Phoenix.PubSub.subscribe(Bullet.PubSub, "device_socket:#{device.id}")

    assert {:ok, erased} = Accounts.erase_user(user)
    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}

    assert erased.deleted_at && erased.suspended_at
    assert erased.name == "Conta removida"
    refute erased.email == email
    # Fiscal retention (5 years): CPF stays, encrypted, and keeps blocking duplicates.
    assert Repo.get!(User, user.id).cpf_encrypted == "52998224725"
    assert {:error, _} = Accounts.register_user(valid_user_attributes(cpf: "52998224725"), & &1)
    assert {:error, :invalid_credentials} = Accounts.login(email, valid_password(), %{})
    # E-mail is free again.
    assert {:ok, _} = Accounts.register_user(valid_user_attributes(email: email), & &1)

    assert Repo.aggregate(from(d in Device, where: d.user_id == ^user.id), :count) == 0
    assert Repo.aggregate(from(t in UserToken, where: t.user_id == ^user.id), :count) == 0
    assert Repo.aggregate(from(w in WatchProgress, where: w.user_id == ^user.id), :count) == 0

    assert %{user_id: nil, ip: nil, end_reason: "account_erased"} =
             Repo.get!(PlaybackSession, p.session_id)

    assert Repo.all(from s in Subscription, where: s.user_id == ^user.id, select: s.status) == [
             :canceled
           ]
  end

  test "suspend revokes everything and is audited; unsuspend restores login" do
    %{user: user, device: device} = watched_subscriber()
    owner = staff_fixture(:support)

    assert {:ok, suspended} = Accounts.suspend_user(user, owner, "compartilhamento")
    assert suspended.suspended_at
    assert Repo.get!(Device, device.id).revoked_at
    assert {:error, :suspended} = Accounts.login(user.email, valid_password(), %{})

    assert %{metadata: %{"reason" => "compartilhamento"}} =
             Repo.get_by(SecurityEvent, kind: "account_suspended", user_id: user.id)

    assert {:ok, _} = Accounts.unsuspend_user(suspended, owner)
    assert {:ok, _} = Accounts.login(user.email, valid_password(), %{})
  end

  test "erased accounts can't be unsuspended" do
    %{user: user} = watched_subscriber()
    {:ok, erased} = Accounts.erase_user(user)
    assert {:error, :erased} = Accounts.unsuspend_user(erased, staff_fixture(:owner))
  end

  test "purge_expired applies the retention table" do
    %{user: user, session: p} = watched_subscriber()
    Bullet.Security.log_event("login_failed", user.id, %{ip: "1.1.1.1"})
    Bullet.Security.log_event("login_failed", user.id, %{ip: "2.2.2.2"})

    Repo.update_all(from(s in PlaybackSession, where: s.id == ^p.session_id),
      set: [started_at: DateTime.add(DateTime.utc_now(), -31, :day)]
    )

    [old | _] = Repo.all(from e in SecurityEvent, where: e.user_id == ^user.id)

    Repo.update_all(from(e in SecurityEvent, where: e.id == ^old.id),
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -91, :day)]
    )

    assert %{stream_ips_cleared: 1, security_events_deleted: 1} = Privacy.purge_expired()
    assert %{ip: nil, code: code} = Repo.get!(PlaybackSession, p.session_id)
    # The watermark code survives: leaks stay traceable after the IP is gone.
    assert code == p.code
  end

  describe "Support.search/1" do
    test "a watermark code leads to the account (RF06)" do
      %{user: user, session: p} = watched_subscriber()

      assert [%{user: %{id: id}, matched_code: %{code: code}}] =
               Support.search(String.downcase(p.code))

      assert id == user.id and code == p.code
    end

    test "by e-mail fragment and by id; wildcards are escaped" do
      user = user_fixture(%{email: "fulana.teste@example.com"})
      assert [%{user: %{id: id}}] = Support.search("fulana.teste")
      assert id == user.id
      assert [%{user: %{id: ^id}}] = Support.search(user.id)
      assert [] = Support.search("%")
      assert [] = Support.search("   ")
    end
  end

  defp staff_fixture(role) do
    {:ok, u} = Accounts.set_role(user_fixture(), role)
    u
  end
end
