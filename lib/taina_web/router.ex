defmodule TainaWeb.Router do
  use TainaWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", TainaWeb do
    pipe_through :api
  end
end
