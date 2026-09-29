defmodule Bullet.Security do
  @moduledoc """
  Security audit trail (RF14). Events never carry e-mail or CPF; `user_id`
  is enough to trace back to the account.
  """

  alias Bullet.Repo
  alias Bullet.Security.SecurityEvent

  @kinds ~w(login_failed refresh_reused device_revoked session_limit_hit token_expired watermark_tampered rate_limited account_suspended account_unsuspended)

  @type context :: %{optional(:ip) => String.t() | nil, optional(:user_agent) => String.t() | nil}

  @spec log_event(String.t(), String.t() | nil, context(), map()) ::
          {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def log_event(kind, user_id, ctx \\ %{}, metadata \\ %{}) when kind in @kinds do
    %SecurityEvent{}
    |> SecurityEvent.changeset(%{
      kind: kind,
      user_id: user_id,
      ip: ctx[:ip],
      user_agent: ctx[:user_agent],
      metadata: metadata
    })
    |> Repo.insert()
  end
end
