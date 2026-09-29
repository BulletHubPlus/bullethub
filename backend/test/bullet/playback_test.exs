defmodule Bullet.PlaybackTest do
  use Bullet.DataCase, async: true

  import Bullet.AccountsFixtures
  import Bullet.CatalogFixtures

  alias Bullet.Accounts.User
  alias Bullet.{Catalog, Playback}
  alias Bullet.Playback.{PlaybackSession, Presence}

  defp episode_series do
    c = collection_fixture()
    s1 = season_fixture(c, 1)
    s2 = season_fixture(c, 2)

    [e1, e2, e3] =
      for {season, title} <- [{s1, "E1"}, {s1, "E2"}, {s2, "S2E1"}] do
        m = item_fixture(season, title: title)
        with_asset(m, :ready)
        {:ok, m} = Catalog.publish_media(m)
        m
      end

    {e1, e2, e3}
  end

  # Simulates the channel join: tracks the session in Presence from a live process.
  defp go_live(session_id, user_id) do
    parent = self()
    {:ok, _} = Playback.join_session(session_id, user_id)

    pid =
      spawn(fn ->
        {:ok, _} = Presence.track(self(), Presence.topic(user_id), session_id, %{})
        send(parent, :tracked)
        receive do: (:stop -> :ok)
      end)

    assert_receive :tracked
    pid
  end

  describe "start_session/4" do
    test "gates: e-mail confirmed, active plan, playable media" do
      movie = published_movie_fixture()
      unconfirmed = user_fixture()
      assert {:error, :email_unconfirmed} = Playback.start_session(unconfirmed, movie.id, nil)

      no_plan = Repo.update!(User.confirm_changeset(user_fixture()))
      assert {:error, :no_subscription} = Playback.start_session(no_plan, movie.id, nil)

      user = subscriber_fixture()
      assert {:error, :not_found} = Playback.start_session(user, movie_fixture().id, nil)
      assert {:error, :not_found} = Playback.start_session(user, "garbage", nil)
    end

    test "returns signed source, 6-char code and a watermark without PII" do
      user = subscriber_fixture("padrao", %{email: "carlos.silva@gmail.com"})
      movie = published_movie_fixture()

      assert {:ok, p} = Playback.start_session(user, movie.id, nil)
      assert p.code =~ ~r/^[2-9A-HJ-NP-Z]{6}$/
      assert p.watermark.text == "ca***@gmail.com · #{p.code}"
      assert p.source == %{engine: "native", url: "/dev/sample.mp4"}
      # 150 s media: token never below 5 min, here 150 + 30 min.
      assert_in_delta p.expires, System.os_time(:second) + 150 + 1800, 5
      assert Repo.get!(PlaybackSession, p.session_id).code == p.code
    end

    test "3rd screen on a 2-screen plan → stream_limit; terminating one frees it (RF07)" do
      user = subscriber_fixture("padrao")
      movie = published_movie_fixture()

      {:ok, a} = Playback.start_session(user, movie.id, nil)
      {:ok, b} = Playback.start_session(user, movie.id, nil)
      go_live(a.session_id, user.id)

      assert {:error, {:stream_limit, active}} = Playback.start_session(user, movie.id, nil)
      assert Enum.map(active, & &1.id) |> Enum.sort() == Enum.sort([a.session_id, b.session_id])

      assert Repo.get_by(Bullet.Security.SecurityEvent,
               kind: "session_limit_hit",
               user_id: user.id
             )

      assert :ok = Playback.terminate_session(user, b.session_id)
      assert {:ok, _} = Playback.start_session(user, movie.id, nil)
    end

    test "a stream whose player left no longer counts" do
      user = subscriber_fixture("basico")
      movie = published_movie_fixture()
      {:ok, a} = Playback.start_session(user, movie.id, nil)
      pid = go_live(a.session_id, user.id)
      assert {:error, {:stream_limit, _}} = Playback.start_session(user, movie.id, nil)

      ref = Process.monitor(pid)
      send(pid, :stop)
      assert_receive {:DOWN, ^ref, _, _, _}
      # Presence removes the entry asynchronously once the tracking process dies.
      Process.sleep(50)
      assert {:ok, _} = Playback.start_session(user, movie.id, nil)
    end

    test "only the owner can terminate a session" do
      user = subscriber_fixture()
      {:ok, a} = Playback.start_session(user, published_movie_fixture().id, nil)
      assert {:error, :not_found} = Playback.terminate_session(subscriber_fixture(), a.session_id)
    end
  end

  test "reaper closes sessions that never joined or lost their player" do
    user = subscriber_fixture("familia")
    movie = published_movie_fixture()
    {:ok, stale} = Playback.start_session(user, movie.id, nil)
    {:ok, live} = Playback.start_session(user, movie.id, nil)
    go_live(live.session_id, user.id)

    old = DateTime.add(DateTime.utc_now(), -5, :minute)

    Repo.update_all(from(s in PlaybackSession, where: s.user_id == ^user.id),
      set: [started_at: old]
    )

    Repo.update_all(from(s in PlaybackSession, where: s.id == ^live.session_id),
      set: [joined_at: old]
    )

    assert [id] = Playback.reap_stale_sessions()
    assert id == stale.session_id
    assert %{end_reason: "timeout"} = Repo.get!(PlaybackSession, stale.session_id)
    assert is_nil(Repo.get!(PlaybackSession, live.session_id).ended_at)
  end

  describe "progress" do
    test "upsert, resume, completion and continue watching" do
      user = subscriber_fixture()
      movie = published_movie_fixture()

      Phoenix.PubSub.subscribe(Bullet.PubSub, "user:#{user.id}")
      assert :ok = Playback.save_progress(user.id, movie.id, 42.7, "dev-1")

      assert_receive %Phoenix.Socket.Broadcast{
        event: "progress_updated",
        payload: %{position: 42, device_id: "dev-1"}
      }

      assert Playback.resume_position(user.id, movie.id) == 42
      assert [%{media: %{id: id}}] = Playback.continue_watching(user.id)
      assert id == movie.id

      # 95% of 150 s = completed: leaves "continue watching", restarts from 0.
      assert :ok = Playback.save_progress(user.id, movie.id, 145)
      assert Playback.resume_position(user.id, movie.id) == 0
      assert Playback.continue_watching(user.id) == []
    end

    test "under 30 s isn't worth resuming; bogus input is rejected" do
      user = subscriber_fixture()
      movie = published_movie_fixture()
      :ok = Playback.save_progress(user.id, movie.id, 10)
      assert Playback.resume_position(user.id, movie.id) == 0
      assert {:error, :invalid} = Playback.save_progress(user.id, movie.id, -1)
      assert {:error, :invalid} = Playback.save_progress(user.id, UUIDv7.generate(), 10)
    end
  end

  test "next_media: next in season, then first of next season, then none (RF04)" do
    {e1, e2, e3} = episode_series()
    assert Catalog.next_media(e1).id == e2.id
    assert Catalog.next_media(e2).id == e3.id
    assert Catalog.next_media(e3) == nil
    assert Catalog.next_media(published_movie_fixture()) == nil
  end

  test "mask_email" do
    assert Playback.mask_email("ab@x.com") == "ab***@x.com"
    assert Playback.mask_email("a@x.com") == "a***@x.com"
  end
end
