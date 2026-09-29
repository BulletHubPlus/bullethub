defmodule BulletWeb.Router do
  use BulletWeb, :router

  import BulletWeb.AdminAuth, only: [fetch_admin: 2, redirect_if_admin: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BulletWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; " <>
          "img-src 'self' data: https:; connect-src 'self' https://video.bunnycdn.com; " <>
          "frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'"
    }
  end

  pipeline :api do
    plug :accepts, ["json"]

    plug :put_secure_browser_headers, %{
      "content-security-policy" => "default-src 'none'; frame-ancestors 'none'"
    }

    plug :put_no_store
  end

  pipeline :webhook do
    plug :accepts, ["json"]

    plug BulletWeb.Plugs.RateLimit,
      name: "webhook",
      limit: 600,
      scale: :timer.minutes(1),
      by: [:ip]
  end

  pipeline :authenticated do
    plug BulletWeb.Plugs.RequireAuth
  end

  # admin.bullethub.app - LiveView panel. Host-prefix match also covers
  # admin.localhost in dev.
  scope "/", BulletWeb, host: "admin." do
    pipe_through [:browser, :fetch_admin]

    scope "/" do
      pipe_through :redirect_if_admin

      get "/login", AdminSessionController, :new
      post "/login", AdminSessionController, :create
    end

    delete "/logout", AdminSessionController, :delete

    live_session :admin_staff, on_mount: [{BulletWeb.AdminAuth, :require_staff}] do
      live "/ingest", Admin.IngestLive
    end

    live_session :admin_catalog,
      on_mount: [
        {BulletWeb.AdminAuth, :require_staff},
        {BulletWeb.AdminAuth, {:require_role, [:owner, :editor]}}
      ] do
      live "/", Admin.CatalogLive
      live "/colecoes/nova", Admin.CollectionFormLive, :new
      live "/colecoes/:id", Admin.CollectionLive
      live "/colecoes/:id/editar", Admin.CollectionFormLive, :edit
      live "/midias/nova", Admin.MediaLive, :new
      live "/midias/:id", Admin.MediaLive, :edit
    end

    # RF15: editor never reaches accounts/subscriptions.
    live_session :admin_users,
      on_mount: [
        {BulletWeb.AdminAuth, :require_staff},
        {BulletWeb.AdminAuth, {:require_role, [:owner, :support]}}
      ] do
      live "/usuarios", Admin.UsersLive
      live "/usuarios/:id", Admin.UserLive
    end
  end

  get "/health", BulletWeb.HealthController, :show

  scope "/webhooks", BulletWeb do
    pipe_through :webhook

    post "/bunny", WebhookController, :bunny
  end

  scope "/api", BulletWeb.Api do
    pipe_through :api

    post "/auth/register", AuthController, :register
    post "/auth/login", AuthController, :login
    post "/auth/refresh", AuthController, :refresh
    post "/auth/logout", AuthController, :logout
    post "/auth/confirm", AuthController, :confirm
    post "/auth/password/forgot", AuthController, :forgot_password
    post "/auth/password/reset", AuthController, :reset_password

    scope "/" do
      pipe_through :authenticated

      post "/auth/confirm/resend", AuthController, :resend_confirmation
      get "/me", MeController, :show
      get "/me/export", MeController, :export
      delete "/me", MeController, :delete
      get "/me/devices", MeController, :devices
      delete "/me/devices/:id", MeController, :revoke_device

      get "/catalog/home", CatalogController, :home
      get "/catalog/search", CatalogController, :search
      get "/catalog/genres", CatalogController, :genres
      get "/catalog/browse/:kind", CatalogController, :browse
      put "/me/list/:kind/:id", ListController, :add
      delete "/me/list/:kind/:id", ListController, :remove
      get "/catalog/collections/:slug", CatalogController, :collection
      get "/catalog/movies/:id", CatalogController, :movie

      post "/playback/sessions", PlaybackController, :create
      delete "/playback/sessions/:id", PlaybackController, :delete
      put "/progress/:media_id", PlaybackController, :progress
      get "/captions/:id", PlaybackController, :caption
      post "/telemetry", PlaybackController, :telemetry
    end

    # Unknown API paths must answer JSON, not fall through to the SPA shell.
    match :*, "/*path", NotFoundController, :show
  end

  if Application.compile_env(:bullet, :dev_routes) do
    # Dev only. Swoosh's mailbox preview relies on inline scripts, which the
    # admin CSP (rightly) blocks - so it gets the default headers instead.
    pipeline :dev_tools do
      plug :accepts, ["html", "json"]
      plug :fetch_session
      plug :protect_from_forgery

      plug :put_secure_browser_headers, %{
        "content-security-policy" =>
          "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; " <>
            "img-src 'self' data:; frame-src 'self'; frame-ancestors 'self'"
      }
    end

    scope "/dev" do
      pipe_through :dev_tools

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Everything else on the app host is the SPA shell (client-side routing).
  scope "/", BulletWeb do
    get "/*path", SpaController, :index
  end

  defp put_no_store(conn, _opts), do: Plug.Conn.put_resp_header(conn, "cache-control", "no-store")
end
