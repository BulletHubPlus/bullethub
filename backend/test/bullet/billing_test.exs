defmodule Bullet.BillingTest do
  use Bullet.DataCase, async: true

  import Bullet.AccountsFixtures
  alias Bullet.Billing
  alias Bullet.Billing.Subscription

  test "plans seeded with the PRD stream limits" do
    assert Enum.map(Billing.list_plans(), &{&1.slug, &1.max_streams}) == [
             {"basico", 1},
             {"padrao", 2},
             {"familia", 4}
           ]
  end

  test "access: active/trialing in period; past_due keeps 3 days of grace; canceled never" do
    user = user_fixture()
    assert Billing.access(user) == nil

    {:ok, sub} = Billing.grant(user, "basico", 30)
    assert %{plan: %{max_streams: 1}} = Billing.access(user)

    past = fn days, status ->
      Repo.update!(
        Ecto.Changeset.change(sub,
          status: status,
          current_period_end: DateTime.add(DateTime.utc_now(), -days, :day)
        )
      )
    end

    past.(2, :past_due)
    assert Billing.access(user)
    past.(4, :past_due)
    refute Billing.access(user)

    Repo.update!(
      Ecto.Changeset.change(Repo.reload!(sub),
        status: :canceled,
        current_period_end: DateTime.add(DateTime.utc_now(), 10, :day)
      )
    )

    refute Billing.access(user)
  end

  test "grant replaces the previous manual subscription" do
    user = user_fixture()
    {:ok, _} = Billing.grant(user, "basico")
    {:ok, _} = Billing.grant(user, "familia")
    assert %{plan: %{slug: "familia"}} = Billing.access(user)

    assert Repo.aggregate(
             from(s in Subscription, where: s.user_id == ^user.id and s.status == :active),
             :count
           ) == 1
  end
end
