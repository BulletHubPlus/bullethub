defmodule BulletWeb.UserChannelTest do
  use BulletWeb.ChannelCase, async: true

  import Bullet.AccountsFixtures
  import Bullet.CatalogFixtures

  alias Bullet.{Accounts, Playback}
  alias BulletWeb.{AccessToken, UserSocket}

  # Regression: context broadcasts must reach the client as pushes, not crash
  # the channel in handle_out/3.
  test "progress_updated and device_revoked are pushed to the account's devices" do
    user = subscriber_fixture()
    {:ok, %{device: d1}} = Accounts.login(user.email, valid_password(), %{})
    {:ok, %{device: d2}} = Accounts.login(user.email, valid_password(), %{})

    {:ok, socket} =
      connect(UserSocket, %{}, connect_info: %{auth_token: AccessToken.sign(user.id, d1.id)})

    {:ok, _, chan} = subscribe_and_join(socket, "user:#{user.id}", %{})
    Process.unlink(chan.channel_pid)
    ref = Process.monitor(chan.channel_pid)

    movie = published_movie_fixture()
    :ok = Playback.save_progress(user.id, movie.id, 42, d2.id)
    assert_push "progress_updated", %{position: 42, device_id: device_id}
    assert device_id == d2.id

    :ok = Accounts.revoke_device(user, d2.id)
    assert_push "device_revoked", %{device_id: revoked}
    assert revoked == d2.id

    refute_receive {:DOWN, ^ref, _, _, _}, 50
  end
end
