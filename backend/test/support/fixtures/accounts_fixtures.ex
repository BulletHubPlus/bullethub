defmodule Bullet.AccountsFixtures do
  @moduledoc false
  alias Bullet.Accounts
  alias Bullet.Accounts.User

  @valid_cpfs ~w(52998224725 11144477735 39053344705 12345678909 98765432100)

  def unique_email, do: "user#{System.unique_integer([:positive])}@example.com"
  def valid_password, do: "senha-bem-longa-123"

  # CPF uniqueness is enforced; build valid ones from a counter.
  def unique_cpf do
    base =
      System.unique_integer([:positive])
      |> rem(999_999_999)
      |> Integer.to_string()
      |> String.pad_leading(9, "1")

    digits = base |> String.graphemes() |> Enum.map(&String.to_integer/1)
    d1 = check(digits)
    d2 = check(digits ++ [d1])
    base <> "#{d1}#{d2}"
  end

  def known_cpfs, do: @valid_cpfs

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_email(),
      name: "Assinante Teste",
      password: valid_password(),
      cpf: unique_cpf()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs |> valid_user_attributes() |> Accounts.register_user(&"http://test/confirm/#{&1}")

    user
  end

  @doc "Confirmed account with an active plan - ready to stream."
  def subscriber_fixture(plan \\ "padrao", attrs \\ %{}) do
    user = user_fixture(attrs)
    user = Bullet.Repo.update!(User.confirm_changeset(user))
    {:ok, _} = Bullet.Billing.grant(user, plan)
    user
  end

  def session_fixture(user \\ nil) do
    user = user || user_fixture()
    {:ok, session} = Accounts.login(user.email, valid_password(), %{name: "Teste"})
    session
  end

  defp check(nums) do
    weight = length(nums) + 1

    sum =
      nums |> Enum.with_index() |> Enum.reduce(0, fn {n, i}, acc -> acc + n * (weight - i) end)

    case rem(sum * 10, 11),
      do: (
        10 -> 0
        d -> d
      )
  end
end
