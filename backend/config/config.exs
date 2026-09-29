# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :bullet,
  ecto_repos: [Bullet.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true]

config :bullet, Bullet.Repo,
  migration_primary_key: [type: :binary_id],
  migration_foreign_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime_usec]

config :bullet, Oban,
  engine: Oban.Engines.Basic,
  repo: Bullet.Repo,
  queues: [default: 10, mailers: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24},
    Oban.Plugins.Lifeline,
    {Oban.Plugins.Cron,
     crontab: [
       {"17 4 * * *", Bullet.Workers.PruneTokens},
       {"*/10 * * * *", Bullet.Workers.AssetStatusPoller},
       {"41 3 * * *", Bullet.Workers.PurgeExpiredData}
     ]}
  ]

# Port (Behaviour) for the video provider - see Bullet.Media.Provider.
config :bullet, :media_provider, Bullet.Media.Bunny

config :bullet, :hosts, app: "localhost", admin: "admin.localhost"
config :bullet, :mail_from, {"bullethub", "no-reply@bullethub.app"}

# Access token lives in memory on the SPA; refresh token in an HttpOnly cookie.
config :bullet, :auth,
  access_token_ttl_seconds: 15 * 60,
  refresh_token_ttl_days: 30

# Configures the endpoint
config :bullet, BulletWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BulletWeb.ErrorHTML, json: BulletWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Bullet.PubSub,
  live_view: [signing_salt: "+FJmQ0fv"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :bullet, Bullet.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  bullet: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  bullet: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Caption uploads (.srt). Compile-time in :mime: run `mix deps.compile mime --force` after changing.
config :mime, :types, %{
  "application/x-subrip" => ["srt"],
  "text/vtt" => ["vtt"],
  "application/manifest+json" => ["webmanifest"]
}

# RNF09: request params are logged with these values replaced by [FILTERED].
config :phoenix, :filter_parameters, ~w(password cpf email token access_token refresh_token)

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
