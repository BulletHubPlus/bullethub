defmodule Bullet.Media.Bunny do
  @moduledoc """
  Bunny Stream adapter (https://docs.bunny.net/reference/video_createvideo).
  The library API key never leaves the backend.
  """
  @behaviour Bullet.Media.Provider

  alias Bullet.Security.PlaybackToken

  @base_url "https://video.bunnycdn.com"

  # Bunny Stream status codes → domain status.
  # 0 created, 1 uploaded, 2 processing, 3 transcoding, 4 finished, 5 error, 6 upload failed
  @status %{
    0 => :uploading,
    1 => :processing,
    2 => :processing,
    3 => :processing,
    4 => :ready,
    5 => :failed,
    6 => :failed
  }

  @impl true
  def create_video(title) do
    case Req.post(client(), url: "/library/#{library_id()}/videos", json: %{title: title}) do
      {:ok, %{status: 200, body: %{"guid" => guid}}} -> {:ok, %{video_id: guid}}
      {:ok, resp} -> {:error, {:unexpected_status, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_video(video_id) do
    case Req.get(client(), url: "/library/#{library_id()}/videos/#{video_id}") do
      {:ok, %{status: 200, body: body}} -> {:ok, normalize(body)}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, resp} -> {:error, {:unexpected_status, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete_video(video_id) do
    case Req.delete(client(), url: "/library/#{library_id()}/videos/#{video_id}") do
      {:ok, %{status: status}} when status in [200, 404] -> :ok
      {:ok, resp} -> {:error, {:unexpected_status, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # https://docs.bunny.net/reference/video_addcaption
  @impl true
  def upload_caption(video_id, srclang, label, vtt) do
    body = %{srclang: srclang, label: label, captionsFile: Base.encode64(vtt)}

    case Req.post(client(),
           url: "/library/#{library_id()}/videos/#{video_id}/captions/#{srclang}",
           json: body
         ) do
      {:ok, %{status: 200}} -> :ok
      {:ok, resp} -> {:error, {:unexpected_status, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete_caption(video_id, srclang) do
    case Req.delete(client(),
           url: "/library/#{library_id()}/videos/#{video_id}/captions/#{srclang}"
         ) do
      {:ok, %{status: status}} when status in [200, 404] -> :ok
      {:ok, resp} -> {:error, {:unexpected_status, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def playback_source(video_id, expires) do
    s = secrets()

    url =
      PlaybackToken.embed_url(s[:bunny_embed_token_key], s[:bunny_library_id], video_id, expires)

    %{engine: "bunny", url: url <> "&autoplay=true&preload=true&responsive=true"}
  end

  @doc false
  def normalize(body) do
    %{
      video_id: body["guid"],
      status: Map.get(@status, body["status"], :processing),
      duration_seconds: body["length"],
      resolutions:
        body
        |> Map.get("availableResolutions", "")
        |> to_string()
        |> String.split(",", trim: true),
      storage_bytes: body["storageSize"]
    }
  end

  defp client do
    Req.new(
      base_url: @base_url,
      headers: [{"accesskey", secrets()[:bunny_api_key]}],
      receive_timeout: 15_000,
      retry: :transient
    )
  end

  defp library_id, do: secrets()[:bunny_library_id]
  defp secrets, do: Application.fetch_env!(:bullet, :secrets)
end
