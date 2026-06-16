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
    plug :put_root_layout, html: {TainaWeb.Layouts, :root}
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

  # Telas públicas: wizard de primeiro boot, login e aceite de convite. Os
  # POSTs tradicionais existem porque cookie de sessão só nasce em controller.
  scope "/", TainaWeb do
    pipe_through :browser

    live_session :public, on_mount: [{TainaWeb.Auth, :mount_current_scope}] do
      live "/setup", SetupLive
      live "/login", LoginLive
      live "/convite/:token", InviteAcceptLive
      live "/redefinir/:token", ResetPasswordLive
    end

    post "/setup", SetupController, :create
    post "/login", SessionController, :create
    post "/convite/:token", InviteController, :accept
    post "/redefinir/:token", PasswordController, :update
    delete "/logout", SessionController, :delete
  end

  scope "/", TainaWeb do
    pipe_through [:browser, :require_authenticated]

    live_session :authenticated,
      on_mount: [{TainaWeb.Auth, :require_authenticated}, {TainaWeb.Hooks, :shell}] do
      live "/", HomeLive

      live "/arquivos", FilesLive, :index
      live "/arquivos/pasta/:folder_id", FilesLive, :folder
      live "/arquivos/enviar", UploadLive
      live "/arquivos/lixeira", TrashLive
      live "/arquivos/:id", FilePreviewLive

      live "/fotos", GalleryLive, :grid
      live "/fotos/linha-do-tempo", GalleryLive, :timeline
      live "/fotos/:id", GalleryLive, :viewer

      live "/membros", MembersLive
      live "/membros/convidar", InviteLive
      live "/armazenamento", StorageLive
      live "/conta", AccountLive
    end
  end
end
