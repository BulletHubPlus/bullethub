defmodule BulletWeb.WebhookControllerTest do
  use BulletWeb.ConnCase, async: true

  import Bullet.CatalogFixtures

  defp post_raw(conn, body, signature) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-bunnystream-signature", signature)
    |> post("/webhooks/bunny", body)
  end

  test "valid signature over the exact raw bytes → 200", %{conn: conn} do
    asset = with_asset(movie_fixture(), :processing)
    # Unusual spacing on purpose: the HMAC must be over the bytes, not re-encoded JSON.
    body = ~s({"VideoLibraryId":12345,  "VideoGuid":"#{asset.bunny_video_id}","Status":3})
    assert %{"ok" => true} = conn |> post_raw(body, sign_bunny(body)) |> json_response(200)
  end

  test "bad signature → 401", %{conn: conn} do
    body = ~s({"VideoLibraryId":12345,"VideoGuid":"x","Status":3})

    assert %{"error" => %{"code" => "invalid_signature"}} =
             conn |> post_raw(body, "00") |> json_response(401)
  end
end
