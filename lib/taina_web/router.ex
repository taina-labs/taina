defmodule TainaWeb.Router do
  use TainaWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TainaWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end
end
