defmodule Bullet.Workers.DeliverUserEmail do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 5

  alias Bullet.Accounts
  alias Bullet.Accounts.UserNotifier

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"kind" => kind, "user_id" => user_id, "url" => url}}) do
    user = Accounts.get_user!(user_id)

    case UserNotifier.deliver(String.to_existing_atom(kind), user, url) do
      {:ok, _email} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
