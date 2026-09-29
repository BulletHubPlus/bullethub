defmodule BulletWeb.Plugs.RemoteIp do
  @moduledoc """
  Resolves the client IP behind Traefik. Only when the TCP peer is a private
  address (the proxy on the Docker network) do we trust X-Forwarded-For, and
  then only its right-most entry - the one Traefik appended itself. Anything
  to the left is client-controlled and spoofable.
  """
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with true <- private?(conn.remote_ip),
         [header | _] <- Plug.Conn.get_req_header(conn, "x-forwarded-for"),
         last when is_binary(last) <- header |> String.split(",") |> List.last(),
         {:ok, ip} <- last |> String.trim() |> String.to_charlist() |> :inet.parse_address() do
      %{conn | remote_ip: ip}
    else
      _ -> conn
    end
  end

  @doc false
  def private?({10, _, _, _}), do: true
  def private?({172, b, _, _}) when b in 16..31, do: true
  def private?({192, 168, _, _}), do: true
  def private?({127, _, _, _}), do: true
  def private?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  def private?({a, _, _, _, _, _, _, _}) when a in 0xFC00..0xFDFF, do: true

  def private?({0, 0, 0, 0, 0, 0xFFFF, a, b}),
    do: private?({div(a, 256), rem(a, 256), div(b, 256), rem(b, 256)})

  def private?(_), do: false
end
