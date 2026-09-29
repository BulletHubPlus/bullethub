defmodule Bullet.Ingest do
  @moduledoc """
  Ingest context (RF08, RF10). Video bytes never touch this server:

    1. `start_upload/1` creates the video at the provider and returns a signed
       TUS credential valid for that single `video_id` (24 h);
    2. the browser uploads straight to Bunny with tus-js-client;
    3. Bunny calls `POST /webhooks/bunny`; `accept_bunny_webhook/2` verifies the
       HMAC, stores the event idempotently and enqueues processing in the same
       transaction;
    4. `ProcessWebhookEvent` / `AssetStatusPoller` move the asset through its
       state machine and broadcast on `"admin:ingest"`.
  """

  import Ecto.Query
  require Logger

  alias Bullet.Catalog.Media
  alias Bullet.Ingest.{MediaAsset, WebhookEvent}
  alias Bullet.Media.Provider
  alias Bullet.Repo
  alias Bullet.Security.PlaybackToken
  alias Bullet.Workers.ProcessWebhookEvent

  @topic "admin:ingest"
  @tus_endpoint "https://video.bunnycdn.com/tusupload"
  @tus_ttl 24 * 60 * 60

  # Bunny *webhook* status codes (different from the REST API's video.status).
  # https://docs.bunny.net/stream/webhooks
  @webhook_status %{
    0 => :processing,
    1 => :processing,
    2 => :processing,
    3 => :ready,
    4 => :processing,
    5 => :failed,
    7 => :processing,
    8 => :failed
  }

  def subscribe, do: Phoenix.PubSub.subscribe(Bullet.PubSub, @topic)

  ## Upload

  @type tus_credentials :: %{
          endpoint: String.t(),
          library_id: String.t(),
          video_id: String.t(),
          signature: String.t(),
          expires: integer(),
          title: String.t()
        }

  @doc """
  Returns TUS credentials for the media's asset, creating the provider video on
  first upload and a fresh one when re-uploading a `failed` asset. An asset in
  `uploading` gets new credentials for the same video, so tus-js-client can
  resume after the browser was closed.
  """
  @spec start_upload(Media.t()) ::
          {:ok, MediaAsset.t(), tus_credentials()} | {:error, :already_uploaded | term()}
  def start_upload(%Media{} = media) do
    case Repo.preload(media, :asset, force: true).asset do
      nil -> create_asset(media)
      %MediaAsset{status: :uploading} = asset -> {:ok, asset}
      %MediaAsset{status: :failed} = asset -> replace_failed_asset(asset, media)
      %MediaAsset{} -> {:error, :already_uploaded}
    end
    |> case do
      {:ok, asset} -> {:ok, asset, tus_credentials(asset, media.title)}
      error -> error
    end
  end

  defp create_asset(media) do
    with {:ok, %{video_id: video_id}} <- Provider.create_video(media.title) do
      %MediaAsset{media_id: media.id}
      |> MediaAsset.create_changeset(video_id)
      |> Repo.insert()
      |> tap(&broadcast_result/1)
    end
  end

  defp replace_failed_asset(asset, media) do
    old_video_id = asset.bunny_video_id

    with {:ok, %{video_id: video_id}} <- Provider.create_video(media.title),
         {:ok, asset} <-
           asset
           |> MediaAsset.transition_changeset(:uploading, %{bunny_video_id: video_id, error: nil})
           |> Repo.update() do
      discard_video(old_video_id)
      broadcast(asset)
      {:ok, asset}
    end
  end

  def tus_credentials(%MediaAsset{bunny_video_id: video_id}, title) do
    secrets = Application.fetch_env!(:bullet, :secrets)
    expires = System.os_time(:second) + @tus_ttl

    %{
      endpoint: @tus_endpoint,
      library_id: secrets[:bunny_library_id],
      video_id: video_id,
      signature:
        PlaybackToken.tus_signature(
          secrets[:bunny_library_id],
          secrets[:bunny_api_key],
          expires,
          video_id
        ),
      expires: expires,
      title: title
    }
  end

  @doc "Browser reported the TUS upload finished."
  def mark_uploaded(%MediaAsset{} = asset), do: advance(asset, :processing)

  @doc """
  Dev/test only (Fake provider): pretend Bunny encoded the video, so the whole
  admin flow can be exercised without a Bunny account.
  """
  def simulate_encoding(%MediaAsset{} = asset) do
    if Provider.impl() == Bullet.Media.Fake do
      with {:ok, video} <- Provider.get_video(asset.bunny_video_id),
           do: advance(asset, :ready, metadata(video))
    else
      {:error, :not_available}
    end
  end

  ## Webhook

  @doc """
  Verifies and stores a Bunny Stream webhook. Signature: HMAC-SHA256 of the raw
  body keyed with the library's **read-only** API key, lowercase hex, in
  `X-BunnyStream-Signature`.
  """
  @spec accept_bunny_webhook(binary(), String.t() | nil) ::
          {:ok, :accepted | :duplicate | :ignored} | {:error, :invalid_signature | :bad_payload}
  def accept_bunny_webhook(raw_body, signature) do
    with :ok <- verify_signature(raw_body, signature),
         {:ok, %{"VideoGuid" => guid, "Status" => status} = payload}
         when is_binary(guid) and is_integer(status) <-
           Jason.decode(raw_body),
         :ok <- verify_library(payload) do
      store_event("bunny", "#{guid}:#{status}", payload)
    else
      {:error, :invalid_signature} = error -> error
      :ignored -> {:ok, :ignored}
      _ -> {:error, :bad_payload}
    end
  end

  defp verify_signature(raw_body, signature) when is_binary(signature) do
    key = Application.fetch_env!(:bullet, :secrets)[:bunny_webhook_key]
    expected = :crypto.mac(:hmac, :sha256, key, raw_body) |> Base.encode16(case: :lower)

    if Plug.Crypto.secure_compare(expected, String.downcase(signature)),
      do: :ok,
      else: {:error, :invalid_signature}
  end

  defp verify_signature(_, _), do: {:error, :invalid_signature}

  # Another library's webhook pointed at us is ignored, not an error.
  defp verify_library(%{"VideoLibraryId" => lib}) do
    if to_string(lib) == Application.fetch_env!(:bullet, :secrets)[:bunny_library_id],
      do: :ok,
      else: :ignored
  end

  defp verify_library(_), do: :ignored

  # insert_all reports the rows actually written. Repo.insert with on_conflict:
  # :nothing can't tell a duplicate apart here: UUIDv7 ids are generated
  # client-side, so the returned struct always carries an id.
  defp store_event(provider, event_id, payload) do
    now = DateTime.utc_now()

    row = %{
      id: UUIDv7.generate(),
      provider: provider,
      event_id: event_id,
      payload: payload,
      inserted_at: now,
      updated_at: now
    }

    Repo.transaction(fn ->
      case Repo.insert_all(WebhookEvent, [row],
             on_conflict: :nothing,
             conflict_target: [:provider, :event_id]
           ) do
        {0, _} ->
          :duplicate

        {1, _} ->
          Oban.insert!(ProcessWebhookEvent.new(%{webhook_event_id: row.id}))
          :accepted
      end
    end)
  end

  @doc "Job body: applies one stored Bunny event to its asset."
  def process_webhook_event(event_id) do
    event = Repo.get!(WebhookEvent, event_id)

    result =
      if event.processed_at do
        :ok
      else
        apply_bunny_event(event.payload)
      end

    error = if match?({:error, _}, result), do: inspect(elem(result, 1))

    event
    |> Ecto.Changeset.change(processed_at: DateTime.utc_now(), error: error)
    |> Repo.update!()

    result
  end

  defp apply_bunny_event(%{"VideoGuid" => guid, "Status" => status}) do
    with {:ok, target} <- Map.fetch(@webhook_status, status),
         %MediaAsset{} = asset <- Repo.get_by(MediaAsset, bunny_video_id: guid) do
      apply_remote(asset, target)
    else
      :error -> :ok
      nil -> {:error, :unknown_video}
    end
  end

  # "ready" pulls duration/resolutions/size from the provider before transitioning.
  defp apply_remote(asset, :ready) do
    case Provider.get_video(asset.bunny_video_id) do
      {:ok, video} -> advance(asset, :ready, metadata(video))
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_remote(asset, :failed), do: advance(asset, :failed, %{error: "encoding_failed"})
  defp apply_remote(asset, target), do: advance(asset, target)

  ## Poller (webhook lost or delayed)

  @stuck_after_minutes 30
  @timeout_hours 6

  @doc """
  Reconciles assets stuck in `processing` for 30+ min with the provider, and
  fails those stuck for 6+ h (PRD §9, §15).
  """
  def reconcile_stuck_assets do
    stuck =
      Repo.all(
        from a in MediaAsset,
          where:
            a.status == :processing and a.status_changed_at < ago(@stuck_after_minutes, "minute")
      )

    Enum.map(stuck, &reconcile/1)
  end

  defp reconcile(asset) do
    timed_out? =
      DateTime.diff(DateTime.utc_now(), asset.status_changed_at, :hour) >= @timeout_hours

    case Provider.get_video(asset.bunny_video_id) do
      {:ok, %{status: :ready} = video} -> advance(asset, :ready, metadata(video))
      {:ok, %{status: :failed}} -> advance(asset, :failed, %{error: "encoding_failed"})
      _ when timed_out? -> advance(asset, :failed, %{error: "timeout"})
      _ -> {:ok, asset}
    end
  end

  ## State machine driver

  @doc """
  Moves an asset to `target` through valid transitions only (see
  `MediaAsset.path/2`). A late signal for a state already reached is a no-op;
  an impossible one (e.g. ready → processing) is logged and ignored.
  """
  @spec advance(MediaAsset.t(), MediaAsset.status(), map()) ::
          {:ok, MediaAsset.t()} | {:error, :invalid_transition | Ecto.Changeset.t()}
  def advance(%MediaAsset{} = asset, target, attrs \\ %{}) do
    asset = Repo.reload!(asset)

    case MediaAsset.path(asset.status, target) do
      {:ok, []} ->
        {:ok, asset}

      {:ok, steps} ->
        steps |> apply_steps(asset, target, attrs) |> tap(&broadcast_result/1)

      :error ->
        Logger.warning("ingest: ignored #{asset.status} → #{target} for asset #{asset.id}")
        {:error, :invalid_transition}
    end
  end

  # All steps in one transaction: a two-step catch-up lands fully or not at all.
  defp apply_steps(steps, asset, target, attrs) do
    Repo.transaction(fn -> Enum.reduce(steps, asset, &transition!(&2, &1, target, attrs)) end)
  end

  # Metadata (duration, error, …) belongs to the final step only.
  defp transition!(asset, step, target, attrs) do
    attrs = if step == target, do: attrs, else: %{}

    case asset |> MediaAsset.transition_changeset(step, attrs) |> Repo.update() do
      {:ok, updated} -> updated
      {:error, cs} -> Repo.rollback(cs)
    end
  end

  defp metadata(video) do
    %{
      duration_seconds: video.duration_seconds,
      encoded_resolutions: video.resolutions,
      storage_bytes: video.storage_bytes
    }
  end

  ## Dashboard

  def list_assets(limit \\ 100) do
    Repo.all(
      from a in MediaAsset,
        order_by: [desc: a.status_changed_at],
        limit: ^limit,
        preload: [media: [:collection, :season]]
    )
  end

  def status_counts do
    Repo.all(from a in MediaAsset, group_by: a.status, select: {a.status, count(a.id)})
    |> Map.new()
  end

  ## Helpers

  def thumbnail_url(%MediaAsset{status: :ready, bunny_video_id: id}) do
    case Application.get_env(:bullet, :secrets)[:bunny_cdn_hostname] do
      host when is_binary(host) and host != "" -> "https://#{host}/#{id}/thumbnail.jpg"
      _ -> nil
    end
  end

  def thumbnail_url(_), do: nil

  @doc "Best-effort removal of the provider video (media deleted or asset replaced)."
  def discard_remote_asset(nil), do: :ok
  def discard_remote_asset(%MediaAsset{bunny_video_id: id}), do: discard_video(id)

  defp discard_video(nil), do: :ok

  defp discard_video(video_id) do
    case Provider.delete_video(video_id) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("ingest: could not delete provider video #{video_id}: #{inspect(reason)}")
        :ok
    end
  end

  defp broadcast_result({:ok, %MediaAsset{} = asset}), do: broadcast(asset)
  defp broadcast_result(_), do: :ok

  defp broadcast(%MediaAsset{} = asset) do
    Phoenix.PubSub.broadcast(Bullet.PubSub, @topic, {:asset_status, asset})
  end
end
