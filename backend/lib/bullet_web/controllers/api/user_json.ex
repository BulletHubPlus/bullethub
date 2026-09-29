defmodule BulletWeb.Api.UserJSON do
  @moduledoc false
  alias Bullet.Accounts.{Device, User}

  # CPF is never serialized; the account page will show it masked in a later phase.
  def user(%User{} = u) do
    %{id: u.id, email: u.email, name: u.name, role: u.role, confirmed: not is_nil(u.confirmed_at)}
  end

  @doc "Account page only. CPF masked (LGPD minimization): 529.***.***-25."
  def account(%User{cpf_encrypted: cpf}), do: %{cpf_masked: mask_cpf(cpf)}

  defp mask_cpf(<<a::binary-size(3), _::binary-size(6), b::binary-size(2)>>),
    do: "#{a}.***.***-#{b}"

  defp mask_cpf(_), do: nil

  def subscription(nil), do: nil

  def subscription(%Bullet.Billing.Subscription{} = s) do
    %{
      status: s.status,
      current_period_end: s.current_period_end,
      plan: %{slug: s.plan.slug, name: s.plan.name, max_streams: s.plan.max_streams}
    }
  end

  def device(%Device{} = d, current_device_id) do
    %{
      id: d.id,
      name: d.name,
      user_agent: d.user_agent,
      last_seen_at: d.last_seen_at,
      created_at: d.inserted_at,
      current: d.id == current_device_id
    }
  end
end
