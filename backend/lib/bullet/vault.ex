defmodule Bullet.Vault do
  @moduledoc "AES-GCM vault for PII at rest (RNF09). Key comes from CLOAK_KEY."
  use Cloak.Vault, otp_app: :bullet
end
