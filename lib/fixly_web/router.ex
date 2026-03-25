defmodule FixlyWeb.Router do
  use FixlyWeb, :router

  import FixlyWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FixlyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FixlyWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Public QR ticket submission (no auth required)
  scope "/r", FixlyWeb do
    pipe_through :browser

    live_session :public_ticket,
      on_mount: [{FixlyWeb.UserAuth, :mount_current_scope}],
      layout: {FixlyWeb.Layouts, :public} do
      live "/:qr_code_id", Public.TicketSubmitLive, :new
    end
  end

  # Admin routes (authenticated)
  scope "/admin", FixlyWeb.Admin do
    pipe_through [:browser, :require_authenticated_user]

    live_session :admin,
      on_mount: [{FixlyWeb.UserAuth, :ensure_authenticated}],
      layout: {FixlyWeb.Layouts, :app} do
      live "/", DashboardLive, :index
      live "/tickets", TicketListLive, :index
      live "/tickets/:id", TicketDetailLive, :show
      live "/locations", LocationTreeLive, :index
      live "/assets", AssetsLive, :index
      live "/ai-review", AIReviewLive, :index
      live "/analytics", AnalyticsLive, :index
    end
  end

  # Export routes (authenticated, non-LiveView)
  scope "/admin/export", FixlyWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/tickets.csv", ExportController, :tickets_csv
    get "/analytics.csv", ExportController, :analytics_csv
  end

  # Contractor routes (authenticated)
  scope "/contractor", FixlyWeb.Contractor do
    pipe_through [:browser, :require_authenticated_user]

    live_session :contractor,
      on_mount: [{FixlyWeb.UserAuth, :ensure_authenticated}],
      layout: {FixlyWeb.Layouts, :app} do
      live "/tickets", TicketListLive, :index
      live "/tickets/:id", TicketDetailLive, :show
    end
  end

  # Technician routes (authenticated)
  scope "/tech", FixlyWeb.Technician do
    pipe_through [:browser, :require_authenticated_user]

    live_session :technician,
      on_mount: [{FixlyWeb.UserAuth, :ensure_authenticated}],
      layout: {FixlyWeb.Layouts, :app} do
      live "/tickets", MyTicketsLive, :index
    end
  end

  # Resident routes (authenticated)
  scope "/my", FixlyWeb.Resident do
    pipe_through [:browser, :require_authenticated_user]

    live_session :resident,
      on_mount: [{FixlyWeb.UserAuth, :ensure_authenticated}],
      layout: {FixlyWeb.Layouts, :app} do
      live "/tickets", MyTicketsLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", FixlyWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:fixly, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FixlyWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", FixlyWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", FixlyWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", FixlyWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
