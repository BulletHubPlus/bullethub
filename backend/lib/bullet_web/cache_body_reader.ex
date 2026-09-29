defmodule BulletWeb.CacheBodyReader do
  @moduledoc """
  Keeps the raw request body for `/webhooks/*` so signatures can be verified
  over the exact bytes received. Other routes are untouched.
  """

  def read_body(%Plug.Conn{path_info: ["webhooks" | _]} = conn, opts) do
    with {:ok, body, conn} <- Plug.Conn.read_body(conn, opts) do
      {:ok, body, Plug.Conn.assign(conn, :raw_body, [body | conn.assigns[:raw_body] || []])}
    end
  end

  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)

  def raw_body(conn),
    do: conn.assigns |> Map.get(:raw_body, []) |> Enum.reverse() |> IO.iodata_to_binary()
end
