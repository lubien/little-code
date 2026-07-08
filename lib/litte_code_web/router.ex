defmodule LitteCodeWeb.Router do
  use LitteCodeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LitteCodeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug LitteCodeWeb.Plugs.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LitteCodeWeb do
    pipe_through :browser

    live_session :default, on_mount: {LitteCodeWeb.LiveHooks, :set_locale} do
      live "/", HomeLive, :index
    end

    get "/l/:hash", LinkController, :show
    put "/locale/:locale", LocaleController, :update
    post "/locale/:locale", LocaleController, :update
  end

  # Plausible analytics reverse proxy. Not part of the `:browser` pipeline
  # — skips CSRF (beacons don't send tokens) and session bookkeeping.
  scope "/", LitteCodeWeb do
    get "/js/:filename", PlausibleProxyController, :script
    post "/api/event", PlausibleProxyController, :event

    # Readiness probe for Fly.io blue/green deploys and uptime monitors.
    get "/up", HealthController, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", LitteCodeWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:litte_code, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LitteCodeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
