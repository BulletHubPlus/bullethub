defmodule Bullet.Security.PlaybackToken do
  @moduledoc """
  Pure signing functions for Bunny Stream. No I/O, no config reads: callers pass
  the keys in, which keeps this module trivially testable and auditable.

  * Embed view token - https://docs.bunny.net/stream/token-authentication
  * TUS upload signature - https://docs.bunny.net/stream/tus-resumable-uploads
  """

  @embed_base "https://iframe.mediadelivery.net/embed"
  @min_ttl 5 * 60
  @slack 30 * 60

  @doc """
  Expiration for a playback token: the whole media plus 30 min slack, never
  under 5 min, so a 2 h film doesn't expire mid-play (PRD §5.5).
  """
  @spec expires_at(non_neg_integer() | nil, integer()) :: integer()
  def expires_at(duration_seconds, now_unix) do
    now_unix + max((duration_seconds || 0) + @slack, @min_ttl)
  end

  @doc "`SHA256_HEX(token_security_key + video_id + expires)`."
  @spec embed_token(String.t(), String.t(), integer()) :: String.t()
  def embed_token(key, video_id, expires) do
    sha256_hex(key <> video_id <> Integer.to_string(expires))
  end

  @spec embed_url(String.t(), String.t(), String.t(), integer()) :: String.t()
  def embed_url(key, library_id, video_id, expires) do
    query =
      URI.encode_query(%{
        "token" => embed_token(key, video_id, expires),
        "expires" => expires
      })

    "#{@embed_base}/#{library_id}/#{video_id}?#{query}"
  end

  @doc "`SHA256(library_id + api_key + expiration_time + video_id)` for the TUS upload headers."
  @spec tus_signature(String.t(), String.t(), integer(), String.t()) :: String.t()
  def tus_signature(library_id, api_key, expires, video_id) do
    sha256_hex(library_id <> api_key <> Integer.to_string(expires) <> video_id)
  end

  defp sha256_hex(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
end
