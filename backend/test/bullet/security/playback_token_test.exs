defmodule Bullet.Security.PlaybackTokenTest do
  use ExUnit.Case, async: true

  alias Bullet.Security.PlaybackToken

  # Vectors computed independently with Python hashlib.
  test "embed token matches SHA256_HEX(key + video_id + expires)" do
    assert PlaybackToken.embed_token("secret-key", "6f1c-video", 1_790_000_000) ==
             "5685b1aa851f0e03537a40e712798804ecf14eb1abcd303d8eb2ce77003a3eab"
  end

  test "TUS signature matches SHA256(library_id + api_key + expires + video_id)" do
    assert PlaybackToken.tus_signature("12345", "api-key", 1_790_000_000, "6f1c-video") ==
             "11d24fff2ae36e8c1d2dd7f46b26a051c63b4d87b7c65d681b54c65f90c6d5a6"
  end

  test "embed_url carries token and expires" do
    url = PlaybackToken.embed_url("secret-key", "999", "6f1c-video", 1_790_000_000)
    uri = URI.parse(url)

    assert uri.host == "iframe.mediadelivery.net"
    assert uri.path == "/embed/999/6f1c-video"

    assert URI.decode_query(uri.query) == %{
             "token" => "5685b1aa851f0e03537a40e712798804ecf14eb1abcd303d8eb2ce77003a3eab",
             "expires" => "1790000000"
           }
  end

  describe "expires_at/2" do
    test "covers the full media plus 30 min" do
      assert PlaybackToken.expires_at(7200, 1000) == 1000 + 7200 + 1800
    end

    test "never less than 5 min, even with unknown duration" do
      assert PlaybackToken.expires_at(nil, 1000) >= 1000 + 300
      assert PlaybackToken.expires_at(0, 1000) >= 1000 + 300
    end
  end
end
