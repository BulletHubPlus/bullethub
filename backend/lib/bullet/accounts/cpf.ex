defmodule Bullet.Accounts.CPF do
  @moduledoc """
  CPF validation (check digits) and the keyed hash used for uniqueness.

  The hash uses a key separate from the encryption key, so uniqueness can be
  enforced without ever decrypting `cpf_encrypted`.
  """

  @doc "Strips formatting. Returns 11 digits or `nil`."
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil

  def normalize(cpf) when is_binary(cpf) do
    digits = String.replace(cpf, ~r/\D/, "")
    if byte_size(digits) == 11, do: digits
  end

  @spec valid?(String.t() | nil) :: boolean()
  def valid?(cpf) do
    case normalize(cpf) do
      nil ->
        false

      digits ->
        nums = digits |> String.graphemes() |> Enum.map(&String.to_integer/1)

        # Repeated digits (000.000.000-00, 111...) pass the checksum but are invalid.
        Enum.uniq(nums) != [hd(nums)] and
          check_digit(Enum.take(nums, 9)) == Enum.at(nums, 9) and
          check_digit(Enum.take(nums, 10)) == Enum.at(nums, 10)
    end
  end

  @spec hash(String.t()) :: binary()
  def hash(cpf) do
    key = Application.fetch_env!(:bullet, :secrets)[:cpf_hmac_key]
    :crypto.mac(:hmac, :sha256, key, normalize(cpf))
  end

  defp check_digit(nums) do
    weight = length(nums) + 1

    sum =
      nums
      |> Enum.with_index()
      |> Enum.reduce(0, fn {n, i}, acc -> acc + n * (weight - i) end)

    case rem(sum * 10, 11) do
      10 -> 0
      d -> d
    end
  end
end
