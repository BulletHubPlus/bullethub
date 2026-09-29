defmodule BulletWeb.Plugs.RateLimit do
  @moduledoc """
  Hammer-backed limiter. Each `by` dimension is counted separately, so
  `by: [:ip, {:param, "email"}]` limits both per IP and per e-mail. A dimension
  may carry its own limit: `by: [{:ip, 20}, {:param, "email"}]`.

      plug RateLimit, name: "login", limit: 5, scale: :timer.minutes(1), by: [:ip, {:param, "email"}]
  """
  @behaviour Plug

  import Plug.Conn
  alias BulletWeb.ErrorResponse

  @impl true
  def init(opts), do: Map.new(opts)

  @impl true
  def call(conn, %{name: name, limit: limit, scale: scale, by: dims}) do
    Enum.reduce_while(dims, conn, fn
      {dim, dim_limit}, conn when is_integer(dim_limit) ->
        check(conn, key(conn, dim), name, scale, dim_limit)

      dim, conn ->
        check(conn, key(conn, dim), name, scale, limit)
    end)
  end

  defp check(conn, nil, _name, _scale, _limit), do: {:cont, conn}

  defp check(conn, key, name, scale, limit) do
    case Bullet.RateLimit.hit("#{name}:#{key}", scale, limit) do
      {:allow, _count} ->
        {:cont, conn}

      {:deny, retry_after_ms} ->
        conn =
          conn
          |> put_resp_header("retry-after", Integer.to_string(div(retry_after_ms, 1000) + 1))
          |> ErrorResponse.send(
            429,
            "rate_limited",
            "Muitas tentativas. Tente novamente em instantes."
          )

        {:halt, conn}
    end
  end

  defp key(conn, :ip), do: "ip:" <> (conn.remote_ip |> :inet.ntoa() |> to_string())
  defp key(%{assigns: %{current_user: %{id: id}}}, :user), do: "user:" <> id
  defp key(_conn, :user), do: nil

  defp key(conn, {:param, name}) do
    case conn.params[name] do
      value when is_binary(value) and value != "" ->
        "#{name}:" <> String.downcase(String.trim(value))

      _ ->
        nil
    end
  end
end
