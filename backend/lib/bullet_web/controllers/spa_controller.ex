defmodule BulletWeb.SpaController do
  @moduledoc """
  Serves the Vue SPA shell (built by Vite into priv/static/app) for every
  non-API route on the app host, so client-side routing works on reload.
  """
  use BulletWeb, :controller

  @csp Enum.join(
         [
           "default-src 'self'",
           "script-src 'self'",
           # Vue binds :style attributes (watermark position, progress bars).
           "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
           "font-src 'self' https://fonts.gstatic.com",
           "img-src 'self' data: blob: https:",
           "media-src 'self' blob:",
           "connect-src 'self'",
           "frame-src https://iframe.mediadelivery.net",
           "frame-ancestors 'none'",
           "base-uri 'self'",
           "form-action 'self'",
           "object-src 'none'"
         ],
         "; "
       )

  # The path is a compile-time constant, never derived from the request.
  # sobelow_skip ["Traversal.SendFile"]
  def index(conn, _params) do
    index = Application.app_dir(:bullet, "priv/static/app/index.html")

    conn = put_secure_browser_headers(conn, %{"content-security-policy" => @csp})

    if File.exists?(index) do
      conn
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_content_type("text/html")
      |> send_file(200, index)
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(503, "SPA não compilada. Em dev use o Vite: cd frontend && npm run dev")
    end
  end
end
