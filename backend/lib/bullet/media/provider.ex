defmodule Bullet.Media.Provider do
  @moduledoc """
  Port for the video provider (Ports & Adapters, PRD §4). The domain only
  talks to this behaviour; `Bullet.Media.Bunny` is the production adapter and
  `Bullet.Media.Fake` backs dev/test without network.

  The adapter normalizes provider vocabulary (e.g. Bunny status 0-5) into
  the atoms below - the anti-corruption layer lives here.
  """

  @type video_status :: :uploading | :processing | :ready | :failed
  @type video :: %{
          video_id: String.t(),
          status: video_status(),
          duration_seconds: non_neg_integer() | nil,
          resolutions: [String.t()],
          storage_bytes: non_neg_integer() | nil
        }

  @callback create_video(title :: String.t()) :: {:ok, %{video_id: String.t()}} | {:error, term()}
  @callback get_video(video_id :: String.t()) :: {:ok, video()} | {:error, :not_found | term()}
  @callback delete_video(video_id :: String.t()) :: :ok | {:error, term()}

  @typedoc "`engine` picks the SPA's PlayerEngine strategy."
  @type playback_source :: %{engine: String.t(), url: String.t()}

  @doc "Attach a WebVTT caption track to the provider's player."
  @callback upload_caption(
              video_id :: String.t(),
              srclang :: String.t(),
              label :: String.t(),
              vtt :: String.t()
            ) ::
              :ok | {:error, term()}
  @callback delete_caption(video_id :: String.t(), srclang :: String.t()) ::
              :ok | {:error, term()}

  @doc "Signed, expiring source for the player. Pure: no network."
  @callback playback_source(video_id :: String.t(), expires :: integer()) :: playback_source()

  @spec impl() :: module()
  def impl, do: Application.fetch_env!(:bullet, :media_provider)

  def create_video(title), do: impl().create_video(title)
  def get_video(video_id), do: impl().get_video(video_id)
  def delete_video(video_id), do: impl().delete_video(video_id)
  def playback_source(video_id, expires), do: impl().playback_source(video_id, expires)

  def upload_caption(video_id, srclang, label, vtt),
    do: impl().upload_caption(video_id, srclang, label, vtt)

  def delete_caption(video_id, srclang), do: impl().delete_caption(video_id, srclang)
end
