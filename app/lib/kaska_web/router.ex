defmodule KaskaWeb.Router do
  use KaskaWeb, :router

  # Kaska exposes ALL application API over Phoenix Channels (see UserSocket).
  # The HTTP router only carries health checks and (in dev) the Swoosh mailbox preview.

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", KaskaWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  if Application.compile_env(:kaska, :dev_routes) do
    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
