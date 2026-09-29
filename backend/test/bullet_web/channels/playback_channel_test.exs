defmodule BulletWeb.PlaybackChannelTest do
  use BulletWeb.ChannelCase, async: true

  import Bullet.AccountsFixtures
  import Bullet.CatalogFixtures

  alias Bullet.Playback
  alias Bullet.Playback.{PlaybackSession, Presence}
  alias BulletWeb.{AccessToken, UserSocket}

  setup do
    user = subscriber_fixture("basico")
    {:ok, %{device: device}} = Bullet.Accounts.login(user.email, valid_password(), %{})
    movie = published_movie_fixture()
    {:ok, p} = Playback.start_session(user, movie.id, device.id)

    {:ok, socket} =
      connect(UserSocket, %{}, connect_info: %{auth_token: AccessToken.sign(user.id, device.id)})

    %{user: user, movie: movie, p: p, socket: socket}
  end

  test "join tracks presence; leaving ends the session and frees the slot", %{
    socket: socket,
    p: p,
    user: user,
    movie: movie
  } do
    {:ok, _, chan} = subscribe_and_join(socket, "playback:#{p.session_id}", %{})
    assert Bullet.Repo.get!(PlaybackSession, p.session_id).joined_at
    assert_eventually(fn -> MapSet.member?(Presence.session_ids(user.id), p.session_id) end)

    Process.unlink(chan.channel_pid)
    ref = leave(chan)
    assert_reply ref, :ok
    assert_eventually(fn -> Bullet.Repo.get!(PlaybackSession, p.session_id).ended_at end)
    assert_eventually(fn -> match?({:ok, _}, Playback.start_session(user, movie.id, nil)) end)
  end

  test "can't join someone else's session", %{p: p} do
    other = subscriber_fixture()
    {:ok, %{device: d}} = Bullet.Accounts.login(other.email, valid_password(), %{})

    {:ok, other_socket} =
      connect(UserSocket, %{}, connect_info: %{auth_token: AccessToken.sign(other.id, d.id)})

    assert {:error, %{reason: "session_not_found"}} =
             subscribe_and_join(other_socket, "playback:#{p.session_id}", %{})
  end

  test "progress over the channel is saved", %{socket: socket, p: p, user: user, movie: movie} do
    {:ok, _, chan} = subscribe_and_join(socket, "playback:#{p.session_id}", %{})
    push(chan, "progress", %{"position" => 64})
    assert_eventually(fn -> Playback.resume_position(user.id, movie.id) == 64 end)
  end

  test "watermark tampering is audited", %{socket: socket, p: p, user: user} do
    {:ok, _, chan} = subscribe_and_join(socket, "playback:#{p.session_id}", %{})
    push(chan, "event", %{"kind" => "watermark_tampered", "detail" => "removed"})

    assert_eventually(fn ->
      Bullet.Repo.get_by(Bullet.Security.SecurityEvent,
        kind: "watermark_tampered",
        user_id: user.id
      )
    end)
  end

  test "terminated from another device → pushes session_terminated and stops", %{
    socket: socket,
    p: p,
    user: user
  } do
    {:ok, _, chan} = subscribe_and_join(socket, "playback:#{p.session_id}", %{})
    Process.unlink(chan.channel_pid)
    ref = Process.monitor(chan.channel_pid)

    :ok = Playback.terminate_session(user, p.session_id)
    assert_push "session_terminated", %{reason: "terminated_by_user"}
    assert_receive {:DOWN, ^ref, _, _, _}
  end

  defp assert_eventually(fun, tries \\ 20) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("condition never became true")
      true -> Process.sleep(25) && assert_eventually(fun, tries - 1)
    end
  end
end
