defmodule BulletWeb.AccessToken do
  @moduledoc """
  Short-lived (15 min) signed access token carrying `{user_id, device_id}`.
  Kept only in SPA memory; the refresh token in an HttpOnly cookie renews it.
  """

  @salt "access token v1"

  def ttl, do: Application.fetch_env!(:bullet, :auth)[:access_token_ttl_seconds]

  def sign(user_id, device_id) do
    Phoenix.Token.sign(BulletWeb.Endpoint, @salt, %{"u" => user_id, "d" => device_id})
  end

  @spec verify(String.t()) ::
          {:ok, %{user_id: String.t(), device_id: String.t()}} | {:error, atom()}
  def verify(token) when is_binary(token) do
    case Phoenix.Token.verify(BulletWeb.Endpoint, @salt, token, max_age: ttl()) do
      {:ok, %{"u" => user_id, "d" => device_id}} ->
        {:ok, %{user_id: user_id, device_id: device_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def verify(_), do: {:error, :missing}
end
