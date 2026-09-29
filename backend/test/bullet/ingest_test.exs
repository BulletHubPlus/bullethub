defmodule Bullet.IngestTest do
  use Bullet.DataCase, async: true
  use Oban.Testing, repo: Bullet.Repo

  import Bullet.CatalogFixtures

  alias Bullet.Ingest
  alias Bullet.Ingest.{MediaAsset, WebhookEvent}
  alias Bullet.Security.PlaybackToken
  alias Bullet.Workers.ProcessWebhookEvent

  defp webhook(guid, status, lib \\ 12_345) do
    Jason.encode!(%{"VideoLibraryId" => lib, "VideoGuid" => guid, "Status" => status})
  end

  describe "start_upload/1" do
    test "creates the provider video and signs TUS for that video only" do
      media = movie_fixture()
      assert {:ok, %MediaAsset{status: :uploading} = asset, creds} = Ingest.start_upload(media)

      assert creds.endpoint == "https://video.bunnycdn.com/tusupload"
      assert creds.video_id == asset.bunny_video_id

      assert creds.signature ==
               PlaybackToken.tus_signature(
                 "12345",
                 "test-api-key",
                 creds.expires,
                 asset.bunny_video_id
               )

      assert_in_delta creds.expires, System.os_time(:second) + 86_400, 5
    end

    test "resuming an upload reuses the same video" do
      media = movie_fixture()
      {:ok, a1, _} = Ingest.start_upload(media)
      {:ok, a2, _} = Ingest.start_upload(media)
      assert a1.bunny_video_id == a2.bunny_video_id
    end

    test "re-upload after failure gets a new video; ready assets refuse" do
      failed = movie_fixture()
      old = with_asset(failed, :failed)

      assert {:ok, %{status: :uploading, bunny_video_id: new_id, error: nil}, _} =
               Ingest.start_upload(failed)

      refute new_id == old.bunny_video_id

      ready = movie_fixture()
      with_asset(ready, :ready)
      assert {:error, :already_uploaded} = Ingest.start_upload(ready)
    end
  end

  describe "accept_bunny_webhook/2" do
    test "rejects a bad signature" do
      body = webhook("x", 3)
      assert {:error, :invalid_signature} = Ingest.accept_bunny_webhook(body, "deadbeef")
      assert {:error, :invalid_signature} = Ingest.accept_bunny_webhook(body, nil)
    end

    test "same event delivered 3× → one row, one job, one transition (Fase 1 exit)" do
      media = movie_fixture()
      asset = with_asset(media, :processing)
      body = webhook(asset.bunny_video_id, 3)

      assert {:ok, :accepted} = Ingest.accept_bunny_webhook(body, sign_bunny(body))
      assert {:ok, :duplicate} = Ingest.accept_bunny_webhook(body, sign_bunny(body))
      assert {:ok, :duplicate} = Ingest.accept_bunny_webhook(body, sign_bunny(body))

      assert Repo.aggregate(WebhookEvent, :count) == 1
      assert [_job] = all_enqueued(worker: ProcessWebhookEvent)

      Ingest.subscribe()
      assert %{success: 1} = Oban.drain_queue(queue: :default)
      assert_receive {:asset_status, %MediaAsset{status: :ready}}

      ready = Repo.reload!(asset)
      assert ready.status == :ready
      assert ready.duration_seconds == 150
      assert ready.encoded_resolutions == ~w(360p 480p 720p 1080p)
      assert Repo.one!(WebhookEvent).processed_at
    end

    test "finished while still 'uploading' walks through processing" do
      asset = with_asset(movie_fixture(), :uploading)
      body = webhook(asset.bunny_video_id, 3)
      {:ok, :accepted} = Ingest.accept_bunny_webhook(body, sign_bunny(body))
      Oban.drain_queue(queue: :default)
      assert Repo.reload!(asset).status == :ready
    end

    test "failure status marks the asset failed" do
      asset = with_asset(movie_fixture(), :processing)
      body = webhook(asset.bunny_video_id, 5)
      {:ok, :accepted} = Ingest.accept_bunny_webhook(body, sign_bunny(body))
      Oban.drain_queue(queue: :default)
      assert %{status: :failed, error: "encoding_failed"} = Repo.reload!(asset)
    end

    test "another library's webhook is ignored; malformed body is rejected" do
      body = webhook("x", 3, 999)
      assert {:ok, :ignored} = Ingest.accept_bunny_webhook(body, sign_bunny(body))
      assert {:error, :bad_payload} = Ingest.accept_bunny_webhook("{}", sign_bunny("{}"))
      assert Repo.aggregate(WebhookEvent, :count) == 0
    end

    test "unknown video is recorded on the event, not retried" do
      body = webhook("unknown-guid", 3)
      {:ok, :accepted} = Ingest.accept_bunny_webhook(body, sign_bunny(body))
      assert %{success: 1} = Oban.drain_queue(queue: :default)
      assert Repo.one!(WebhookEvent).error =~ "unknown_video"
    end
  end

  test "late 'processing' after ready is ignored" do
    asset = with_asset(movie_fixture(), :ready)
    assert {:error, :invalid_transition} = Ingest.advance(asset, :processing)
    assert Repo.reload!(asset).status == :ready
  end

  describe "reconcile_stuck_assets/0" do
    test "asks the provider about assets processing for 30+ min" do
      asset = with_asset(movie_fixture(), :processing)

      Repo.update_all(from(a in MediaAsset, where: a.id == ^asset.id),
        set: [status_changed_at: DateTime.add(DateTime.utc_now(), -45, :minute)]
      )

      Ingest.reconcile_stuck_assets()
      assert Repo.reload!(asset).status == :ready
    end

    test "leaves fresh ones alone" do
      asset = with_asset(movie_fixture(), :processing)
      assert [] = Ingest.reconcile_stuck_assets()
      assert Repo.reload!(asset).status == :processing
    end
  end

  test "thumbnail_url only for ready assets" do
    asset = with_asset(movie_fixture(), :ready)

    assert Ingest.thumbnail_url(asset) ==
             "https://vz-test.b-cdn.net/#{asset.bunny_video_id}/thumbnail.jpg"

    assert Ingest.thumbnail_url(%MediaAsset{status: :processing}) == nil
  end
end
