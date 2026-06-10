defmodule TainaWeb.Router do
  use TainaWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Download de arquivos: sessão por cookie, sem travar o `accept` (o cliente
  # pede o tipo do arquivo, não JSON).
  pipeline :authenticated do
    plug :fetch_session
  end

  scope "/", TainaWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  scope "/", TainaWeb do
    pipe_through :authenticated

    get "/files/:public_id", FileController, :download
    get "/files/:public_id/thumbnail/:size", FileController, :thumbnail
  end
end
