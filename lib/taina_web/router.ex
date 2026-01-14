defmodule TainaWeb.Router do
  use TainaWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TainaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TainaWeb do
    pipe_through :browser

    live "/", HomeLive, :index
  end

  # API routes
  scope "/api", TainaWeb do
    pipe_through :api
  end
end
