defmodule Bullet.Media.Fake do
  @moduledoc "Offline adapter for dev/test. Every video is instantly `:ready`, 150 s long (matches the dev sample)."
  @behaviour Bullet.Media.Provider

  @impl true
  def create_video(_title), do: {:ok, %{video_id: UUIDv7.generate()}}

  @impl true
  def get_video(video_id) do
    {:ok,
     %{
       video_id: video_id,
       status: :ready,
       duration_seconds: 150,
       resolutions: ~w(360p 480p 720p 1080p),
       storage_bytes: 1_000_000
     }}
  end

  @impl true
  def delete_video(_video_id), do: :ok

  @impl true
  def upload_caption(_video_id, _srclang, _label, _vtt), do: :ok

  @impl true
  def delete_caption(_video_id, _srclang), do: :ok

  # Local file from scripts/dev-sample-video.sh, played by the SPA's native engine.
  @impl true
  def playback_source(_video_id, _expires), do: %{engine: "native", url: "/dev/sample.mp4"}
end
