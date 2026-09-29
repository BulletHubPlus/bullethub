defmodule Bullet.Billing do
  @moduledoc """
  Billing context (RF12). Fase 2 only needs "does this user have access and
  how many screens": the payment gateway and its idempotent webhook arrive in
  Fase 3. Until then subscriptions are granted manually (`grant/3`, gateway
  `"manual"`).
  """

  import Ecto.Query

  alias Bullet.Accounts.User
  alias Bullet.Billing.{Plan, Subscription}
  alias Bullet.Repo

  # PRD RF12: past_due keeps access for 3 days after the period ends.
  @past_due_grace_days 3

  def list_plans, do: Repo.all(from p in Plan, where: p.active, order_by: p.max_streams)

  def get_plan_by_slug(slug), do: Repo.get_by(Plan, slug: slug)

  @doc "The subscription that grants access right now, with its plan, or nil."
  @spec access(User.t() | String.t()) :: Subscription.t() | nil
  def access(%User{id: id}), do: access(id)

  def access(user_id) do
    now = DateTime.utc_now()
    grace_cutoff = DateTime.add(now, -@past_due_grace_days, :day)

    Repo.one(
      from s in Subscription,
        where: s.user_id == ^user_id,
        where:
          (s.status in [:trialing, :active] and s.current_period_end > ^now) or
            (s.status == :past_due and s.current_period_end > ^grace_cutoff),
        order_by: [desc: s.current_period_end],
        limit: 1,
        preload: :plan
    )
  end

  @doc """
  Grants (or extends) access manually - support, tests and the pre-gateway
  period. Replaces any current manual subscription of the user.
  """
  def grant(%User{id: user_id}, plan_slug, days \\ 30) do
    with %Plan{} = plan <- get_plan_by_slug(plan_slug) || {:error, :unknown_plan} do
      Repo.transaction(fn ->
        Repo.update_all(
          from(s in Subscription,
            where: s.user_id == ^user_id and s.gateway == "manual" and s.status != :canceled
          ),
          set: [status: :canceled, updated_at: DateTime.utc_now()]
        )

        Repo.insert!(%Subscription{
          user_id: user_id,
          plan_id: plan.id,
          status: :active,
          gateway: "manual",
          current_period_end: DateTime.add(DateTime.utc_now(), days, :day)
        })
        |> Repo.preload(:plan)
      end)
    end
  end
end
