import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :bullet, Bullet.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: String.to_integer(System.get_env("DB_PORT", "5439")),
  database: "bullet_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bullet, BulletWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Q3VjANBjlcts0imMAOrEdh060PMRpCNTOqn2yz7xFYdMB3xxVjtAvaOEBMQQtLfY",
  server: false

# In test we don't send emails
config :bullet, Bullet.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :bullet, Oban, testing: :manual
config :bullet, :media_provider, Bullet.Media.Fake

config :bullet, Bullet.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1",
       key: Base.decode64!("3Jnb0hZiX4prXVvS4Rm/0Pnp8i3Qsr0Aqq/jSo2d+Mo="),
       iv_length: 12}
  ]

config :bullet, :secrets,
  cpf_hmac_key: "test-cpf-hmac-key",
  bunny_library_id: "12345",
  bunny_api_key: "test-api-key",
  bunny_embed_token_key: "test-embed-key",
  bunny_webhook_key: "test-readonly-key",
  bunny_cdn_hostname: "vz-test.b-cdn.net"

config :bullet, :secure_cookies, false

# Argon2 is deliberately slow; make it cheap in tests only.
config :argon2_elixir, t_cost: 1, m_cost: 8

config :bullet, :session_reaper, false
