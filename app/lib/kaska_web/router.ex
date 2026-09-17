defmodule KaskaWeb.Router do
  use KaskaWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :internal do
    plug :accepts, ["json"]
    plug KaskaWeb.Plugs.InternalAuth
  end

  scope "/", KaskaWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  scope "/api/v1", KaskaWeb.Api do
    pipe_through :api

    get "/p/:project_slug", BoardController, :project
    get "/p/:project_slug/tasks/:id", TaskController, :show
    patch "/p/:project_slug/tasks/:id", TaskController, :update
    post "/p/:project_slug/tasks/:id/move", TaskController, :move
    post "/p/:project_slug/tasks/:task_id/comments", CommentController, :create
  end

  scope "/internal", KaskaWeb.Internal do
    pipe_through :internal

    post "/agent_runs/:id/logs", AgentRunController, :logs
    post "/agent_runs/:id/exit", AgentRunController, :exit
  end

  if Application.compile_env(:kaska, :dev_routes) do
    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
