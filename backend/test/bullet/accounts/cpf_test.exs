defmodule Bullet.Accounts.CPFTest do
  use ExUnit.Case, async: true

  alias Bullet.Accounts.CPF

  test "accepts valid CPFs with or without formatting" do
    assert CPF.valid?("529.982.247-25")
    assert CPF.valid?("11144477735")
  end

  test "rejects wrong check digits, repeated digits and wrong length" do
    refute CPF.valid?("529.982.247-24")
    refute CPF.valid?("111.111.111-11")
    refute CPF.valid?("123")
    refute CPF.valid?(nil)
  end

  test "hash is deterministic and ignores formatting" do
    assert CPF.hash("529.982.247-25") == CPF.hash("52998224725")
    refute CPF.hash("52998224725") == CPF.hash("11144477735")
  end
end
