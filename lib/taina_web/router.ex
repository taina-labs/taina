defmodule TainaWeb.Router do
  use TainaWeb, :router

  import Phoenix.LiveDashboard.Router
  import Phoenix.LiveView.Router
  import TainaWeb.API.Auth
  import TainaWeb.Auth

  pipeline :api do
    plug :accepts, ["json"]
  end

  # A API v1 (RFC_005): Bearer de dispositivo, nunca cookie. O `fetch_api_scope`
  # nao barra ninguem; `:api_v1_auth` e `:api_v1_zelador` sao os portoes.
  pipeline :api_v1 do
    plug :accepts, ["json"]
    plug :fetch_api_scope
  end

  pipeline :api_v1_auth do
    plug :require_api_auth
  end

  pipeline :api_v1_zelador do
    plug :require_api_zelador
  end

  pipeline :authenticated do
    plug :fetch_session
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TainaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope
  end

  pipeline :zelador do
    plug :require_zelador
  end

  scope "/", TainaWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  # Superficie v1 (RFC_005 secao 9). Fatia 1: a vertical minima do app
  # (login, navegar, subir, ver). As fatias 2 e 3 entram nos mesmos escopos.
  scope "/api/v1", TainaWeb.API do
    pipe_through :api_v1

    get "/instance", InstanceController, :show
    post "/session", SessionController, :create
  end

  scope "/api/v1", TainaWeb.API do
    pipe_through [:api_v1, :api_v1_auth]

    delete "/session", SessionController, :delete
    get "/me", MeController, :show

    get "/folders", FolderController, :index
    post "/folders", FolderController, :create
    get "/folders/:id", FolderController, :show
    patch "/folders/:id", FolderController, :update
    post "/folders/:id/move", FolderController, :move
    delete "/folders/:id", FolderController, :delete
    get "/contents", FolderController, :contents

    post "/files", FileController, :create
    get "/files/:id", FileController, :show
    patch "/files/:id", FileController, :update
    post "/files/:id/move", FileController, :move
    delete "/files/:id", FileController, :delete
    get "/files/:id/download", FileController, :download
    get "/files/:id/thumbnail/:size", FileController, :thumbnail
    get "/files/:id/access-target", AccessController, :show
    post "/files/:id/access-request", AccessController, :create

    get "/recent", FileController, :recent
    get "/trash", TrashController, :index
    post "/trash/:file_id/restore", TrashController, :restore
    get "/photos", PhotoController, :index
    get "/photos/timeline", PhotoController, :timeline

    get "/devices", DeviceController, :index
    delete "/devices/:id", DeviceController, :delete
    get "/members", MemberController, :index

    get "/access-requests", AccessRequestController, :index
    get "/my-requests", AccessRequestController, :mine
    post "/access-requests/:id/approve", AccessRequestController, :approve
    post "/access-requests/:id/deny", AccessRequestController, :deny

    get "/mural", MuralController, :index
    get "/storage", StorageController, :show
    get "/saude", SaudeController, :show
  end

  scope "/api/v1", TainaWeb.API do
    pipe_through [:api_v1, :api_v1_auth, :api_v1_zelador]

    post "/members", MemberController, :create
    patch "/members/:id", MemberController, :update
    delete "/members/:id", MemberController, :delete
    post "/members/:id/reactivate", MemberController, :reactivate
    delete "/members/:id/invite", MemberController, :revoke_invite
    post "/members/:id/reset-link", MemberController, :reset_link

    patch "/storage/quota", StorageController, :update_quota
    post "/saude/backup", SaudeController, :backup
  end

  scope "/", TainaWeb do
    pipe_through :authenticated

    get "/files/:rkey", FileController, :download
    get "/files/:rkey/thumbnail/:size", FileController, :thumbnail
  end

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
    pipe_through :browser

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
      live "/mural", MuralLive
      live "/saude", SaudeLive
      live "/conta", AccountLive
      live "/conta/pedidos", AccessRequestsLive
    end
  end

  # Painel da máquina (RFC_003 seção 6, camada 3): quem cuida, e só quem cuida.
  # O portão é o papel do Ava, não o ambiente de build.
  scope "/" do
    pipe_through [:browser, :zelador]

    live_dashboard "/painel-do-zelador", metrics: {TainaWeb.Telemetry, :metrics}
  end
end
