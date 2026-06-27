defmodule LapsusCoordinatorWeb.Router do
  use LapsusCoordinatorWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Liveness probe (reverse proxy + deploy health check).
  scope "/", LapsusCoordinatorWeb do
    get "/health", HealthController, :index
  end

  scope "/api", LapsusCoordinatorWeb do
    pipe_through :api
  end
end
