defmodule Bullet.Accounts.UserToken do
  @moduledoc """
  Opaque tokens (refresh, e-mail confirmation, password reset).

  The client holds the raw 32-byte value; the database only stores its
  SHA-256, so a DB leak doesn't hand out usable tokens.
  """
  use Bullet.Schema
  import Ecto.Query

  @rand_size 32
  @contexts ~w(refresh confirm reset admin_session)

  schema "user_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :used_at, :utc_datetime_usec

    belongs_to :user, Bullet.Accounts.User
    belongs_to :device, Bullet.Accounts.Device

    timestamps(updated_at: false)
  end

  @doc "Returns `{raw_url_safe_token, %UserToken{}}` ready to insert."
  def build(%{id: user_id}, context, opts \\ []) when context in @contexts do
    raw = :crypto.strong_rand_bytes(@rand_size)

    token = %__MODULE__{
      token: hash(raw),
      context: context,
      user_id: user_id,
      device_id: opts[:device_id],
      sent_to: opts[:sent_to]
    }

    {Base.url_encode64(raw, padding: false), token}
  end

  @doc "Finds a token by its raw value within its validity window, regardless of `used_at`."
  def by_raw_query(raw, context, validity_seconds) do
    with {:ok, decoded} <- Base.url_decode64(raw, padding: false) do
      query =
        from t in __MODULE__,
          where: t.token == ^hash(decoded) and t.context == ^context,
          where: t.inserted_at > ago(^validity_seconds, "second")

      {:ok, query}
    end
  end

  def by_user_and_contexts_query(user_id, contexts) do
    from t in __MODULE__, where: t.user_id == ^user_id and t.context in ^contexts
  end

  def by_device_query(device_id) do
    from t in __MODULE__, where: t.device_id == ^device_id
  end

  defp hash(raw), do: :crypto.hash(:sha256, raw)
end
