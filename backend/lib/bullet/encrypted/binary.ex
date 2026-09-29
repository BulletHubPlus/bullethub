defmodule Bullet.Encrypted.Binary do
  @moduledoc false
  use Cloak.Ecto.Binary, vault: Bullet.Vault
end
