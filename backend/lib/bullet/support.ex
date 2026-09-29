defmodule Bullet.Support do
  @moduledoc """
  Read side of the admin "Usuários" screens (RF14, RF15, runbook 3).

  The search accepts an e-mail fragment, a user id, or a 6-char watermark
  code: a leaked frame's code leads straight to the account (RF06 acceptance:
  identify the account in under a minute).
  """

  import Ecto.Query

  alias Bullet.Accounts.{Device, User}
  alias Bullet.Billing
  alias Bullet.Playback.PlaybackSession
  alias Bullet.Repo
  alias Bullet.Security.SecurityEvent

  @code ~r/^[2-9A-HJ-NP-Z]{6}$/

  @type hit :: %{user: User.t(), matched_code: PlaybackSession.t() | nil}

  @spec search(String.t()) :: [hit()]
  def search(query) do
    q = String.trim(query || "")

    cond do
      q == "" -> []
      Regex.match?(@code, String.upcase(q)) -> by_code(String.upcase(q))
      match?({:ok, _}, Ecto.UUID.cast(q)) -> by_id(q)
      true -> by_email(q)
    end
  end

  defp by_code(code) do
    case Repo.one(
           from s in PlaybackSession, where: s.code == ^code, preload: [:user, media: :collection]
         ) do
      %PlaybackSession{user: %User{} = user} = s -> [%{user: user, matched_code: s}]
      _ -> []
    end
  end

  defp by_id(id) do
    case Repo.get(User, id) do
      nil -> []
      user -> [%{user: user, matched_code: nil}]
    end
  end

  defp by_email(q) do
    pattern = "%" <> String.replace(q, ~w(% _ \\), &("\\" <> &1)) <> "%"

    Repo.all(
      from u in User, where: ilike(u.email, ^pattern), order_by: [desc: u.inserted_at], limit: 25
    )
    |> Enum.map(&%{user: &1, matched_code: nil})
  end

  def get_user!(id), do: Repo.get!(User, id)

  def overview(%User{id: id} = user, events_since_days \\ 30) do
    %{
      subscription: Billing.access(user),
      devices:
        Repo.all(
          from d in Device, where: d.user_id == ^id, order_by: [desc: d.last_seen_at], limit: 20
        ),
      sessions:
        Repo.all(
          from s in PlaybackSession,
            where: s.user_id == ^id,
            order_by: [desc: s.started_at],
            limit: 25,
            preload: [:device, media: :collection]
        ),
      events:
        Repo.all(
          from e in SecurityEvent,
            where: e.user_id == ^id and e.inserted_at > ago(^events_since_days, "day"),
            order_by: [desc: e.inserted_at],
            limit: 200
        )
    }
  end
end
