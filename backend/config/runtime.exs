import Config

# All secrets are read at runtime so the same image runs in staging and prod.
# A missing secret must crash the boot, never fall back to a default.

if System.get_env("PHX_SERVER") do
  config :bullet, BulletWeb.Endpoint, server: true
end

if config_env() == :prod do
  fetch! = fn name ->
    case System.get_env(name) do
      value when value in [nil, ""] -> raise "environment variable #{name} is required"
      value -> value
    end
  end

  config :bullet, Bullet.Repo,
    url: fetch!.("DATABASE_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: if(System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []),
    parameters: [statement_timeout: "10000"]

  host = System.get_env("PHX_HOST") || "bullethub.app"
  admin_host = System.get_env("ADMIN_HOST") || "admin.#{host}"

  config :bullet, :hosts, app: host, admin: admin_host

  config :bullet, BulletWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    secret_key_base: fetch!.("SECRET_KEY_BASE"),
    check_origin: ["https://#{host}", "https://#{admin_host}"]

  config :bullet, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :bullet, Bullet.Vault,
    ciphers: [
      default:
        {Cloak.Ciphers.AES.GCM,
         tag: "AES.GCM.V1", key: Base.decode64!(fetch!.("CLOAK_KEY")), iv_length: 12}
    ]

  config :bullet, :secrets,
    cpf_hmac_key: fetch!.("CPF_HMAC_KEY"),
    bunny_library_id: fetch!.("BUNNY_LIBRARY_ID"),
    bunny_api_key: fetch!.("BUNNY_API_KEY"),
    bunny_embed_token_key: fetch!.("BUNNY_EMBED_TOKEN_KEY"),
    # Bunny signs webhooks with the library's read-only API key.
    bunny_webhook_key: fetch!.("BUNNY_READONLY_API_KEY"),
    bunny_cdn_hostname: fetch!.("BUNNY_CDN_HOSTNAME")

  config :bullet, Bullet.Mailer,
    adapter: Swoosh.Adapters.Resend,
    api_key: fetch!.("RESEND_API_KEY")

  config :bullet, :mail_from, {"bullethub", System.get_env("MAIL_FROM") || "no-reply@#{host}"}
end
