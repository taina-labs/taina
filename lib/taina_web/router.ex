defmodule TainaWeb.Router do
  use TainaWeb, :router

  import Phoenix.LiveView.Router
  import TainaWeb.Auth

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Download de arquivos: sessão por cookie, sem travar o `accept` (o cliente
  # pede o tipo do arquivo, não JSON).
  pipeline :authenticated do
    plug :fetch_session
  end

  # UI server-rendered (LiveView): sessão + flash + scope da requisição. As
  # rotas HTML/LiveView que usam este pipeline chegam com a fase de UI; a cola
  # de auth (`fetch_current_scope` / `require_authenticated` / `on_mount`) já
  # fica pronta aqui (ver `TainaWeb.Auth`).
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope
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
