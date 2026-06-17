defmodule KaskaWeb.Router do
  use KaskaWeb, :router

  # Kaska exposes ALL application API over Phoenix Channels (see UserSocket).
  # The HTTP router only carries health checks and (in dev) the Swoosh mailbox preview.

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_auth do
    plug :accepts, ["json"]
    plug KaskaWeb.Plugs.ApiAuth
  end

  pipeline :openapi do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: KaskaWeb.ApiSpec
  end

  pipeline :swagger_ui do
    plug :accepts, ["html"]
  end

  scope "/", KaskaWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  scope "/api" do
    pipe_through :openapi

    get "/openapi", OpenApiSpex.Plug.RenderSpec, :show
  end

  scope "/api" do
    pipe_through :swagger_ui

    get "/docs", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi"
  end

  scope "/api/v1", KaskaWeb.Api do
    pipe_through :api_auth

    get "/projects", ProjectController, :index

    get "/p/:project_slug/tasks", TaskController, :index
    get "/p/:project_slug/tasks/:id", TaskController, :show
    patch "/p/:project_slug/tasks/:id", TaskController, :update
    post "/p/:project_slug/tasks/:id/move", TaskController, :move

    get "/p/:project_slug/tasks/:task_id/comments", CommentController, :index
    post "/p/:project_slug/tasks/:task_id/comments", CommentController, :create

    get "/p/:project_slug", BoardController, :project
    get "/p/:project_slug/columns", BoardController, :columns
    get "/p/:project_slug/task_types", BoardController, :task_types
    get "/p/:project_slug/members", BoardController, :members

    get "/agent/events", AgentEventController, :index
    post "/agent/events/:id/ack", AgentEventController, :ack
  end

  if Application.compile_env(:kaska, :dev_routes) do
    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
