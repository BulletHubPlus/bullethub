defmodule BulletWeb.SocketTransportTest do
  @moduledoc """
  Guards the endpoint wiring itself: the channel tests pass connect_info by
  hand and can't see a misconfigured `auth_token` transport option.
  """
  use ExUnit.Case, async: true

  test "/socket enables auth_token at the socket level (where Phoenix 1.8 reads it)" do
    {"/socket", BulletWeb.UserSocket, opts} =
      Enum.find(BulletWeb.Endpoint.__sockets__(), fn {path, _, _} -> path == "/socket" end)

    assert opts[:auth_token] == true
    refute Keyword.has_key?(opts[:websocket], :auth_token)
  end
end
