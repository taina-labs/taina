defmodule TainaWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use TainaWeb, :controller
      use TainaWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  # sw.js is intentionally absent: it is served by a dedicated plug in the
  # Endpoint with a no-cache header so service-worker updates are always picked
  # up (see TainaWeb.Endpoint).
  def static_paths,
    do: ~w(assets fonts icons robots.txt favicon.ico apple-touch-icon.png manifest.webmanifest offline.html)

  # Raiz que o `mix phx.digest` (dentro de `assets.deploy`) fingerprinta. O `~p`
  # do layout emite o nome com hash (`manifest-<hash>.webmanifest`), e o `only`
  # do Plug.Static casa o nome exato: sem `only_matching` esses arquivos dariam
  # 404 no build publicado, deixando a caixa sem manifest nem ícone (o iOS, sem
  # manifest, abre a PWA com a moldura do Safari em vez de em tela cheia).
  def static_path_prefixes, do: ~w(favicon apple-touch-icon manifest robots offline)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Phoenix.Controller

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json], layouts: [html: TainaWeb.Layouts]
      use Gettext, backend: TainaWeb.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions for HTML rendering (forms, etc.)
      import Phoenix.HTML

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      use Gettext, backend: TainaWeb.Gettext

      import Phoenix.Controller, only: [get_csrf_token: 0]
      import Phoenix.HTML
      import TainaWeb.CoreComponents

      alias Phoenix.LiveView.JS

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: TainaWeb.Endpoint,
        router: TainaWeb.Router,
        statics: TainaWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
