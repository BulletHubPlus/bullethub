defmodule BulletWeb.Plugs.RemoteIpTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias BulletWeb.Plugs.RemoteIp

  defp run(peer, xff) do
    conn(:get, "/")
    |> Map.put(:remote_ip, peer)
    |> put_req_header("x-forwarded-for", xff)
    |> RemoteIp.call([])
  end

  test "behind the proxy, takes the right-most X-Forwarded-For entry" do
    assert run({172, 18, 0, 5}, "6.6.6.6, 200.1.2.3").remote_ip == {200, 1, 2, 3}
  end

  test "ignores X-Forwarded-For from a public peer (direct hit, spoof attempt)" do
    assert run({200, 1, 2, 3}, "10.0.0.1").remote_ip == {200, 1, 2, 3}
  end

  test "keeps the peer when the header is garbage" do
    assert run({10, 0, 0, 2}, "not-an-ip").remote_ip == {10, 0, 0, 2}
  end
end
