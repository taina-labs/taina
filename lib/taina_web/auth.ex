defmodule TainaWeb.Auth do
  @moduledoc """
  Cola de autenticação entre a sessão (cookie) e o `Taina.Scope` que todo
  context exige. Resolve quem está logado uma única vez e deixa o `:current_scope`
  pronto tanto para controllers/plugs (a conn) quanto para LiveViews (o socket).

  - `fetch_current_scope/2` — plug: assina `:current_scope` (um `Scope` ou `nil`).
  - `require_authenticated/2` — plug: barra requisições sem sessão.
  - `on_mount/4` — callbacks de LiveView (`:mount_current_scope`,
    `:require_authenticated`).

  O scope carrega o Ava **e** a Tekoa (`Maraca.get_session_user/1` pré-carrega a
  Tekoa), então os contexts conseguem entrar em `Repo.with_tekoa/2` direto.

  Quem ainda não tem a tela de login (próximo PR de UI) é mandado para
  `/login` — referenciado por string de propósito, já que a rota nasce com a UI.
  """

  use TainaWeb, :verified_routes

  # `redirect/2` e `put_flash/3` existem tanto em `Phoenix.Controller` (conn)
  # quanto em `Phoenix.LiveView` (socket). Importamos só o lado da conn e
  # qualificamos o lado do socket para não ficar ambíguo.
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]
  import Plug.Conn, only: [assign: 3, halt: 1, put_session: 3, configure_session: 2, clear_session: 1]

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias Taina.Maraca
  alias Taina.Maraca.Ava
  alias Taina.Scope

  @login_path "/login"

  @doc """
  Inicia a sessão de um Ava autenticado.

  Rotaciona o id de sessão e descarta o conteúdo anterior (**anti session
  fixation**) antes de gravar o `:ava_id`. O controller de login (fase de UI)
  chama isto logo após `Maraca.authenticate/3` e então redireciona; o
  `:current_scope` é remontado na próxima requisição por `fetch_current_scope/2`
  (que pré-carrega a Tekoa), então não o assinamos aqui.
  """
  def log_in_ava(conn, %Ava{} = ava) do
    conn
    |> renew_session()
    |> put_session(:ava_id, ava.public_id)
  end

  @doc """
  Encerra a sessão (logout): rotaciona o id e descarta todo o conteúdo. Espelho
  de `log_in_ava/2`; deixa a conn pronta para o redirect pós-logout.
  """
  def log_out_ava(conn) do
    renew_session(conn)
  end

  # Gera um novo id de sessão e zera o conteúdo anterior. Previne fixation: um id
  # capturado antes do login não vale depois dele.
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Plug: resolve a sessão e assina `:current_scope` (um `Taina.Scope` quando há
  login válido, senão `nil`). Não barra ninguém — só popula o scope.
  """
  def fetch_current_scope(conn, _opts) do
    assign(conn, :current_scope, scope_from(conn))
  end

  @doc """
  Plug: exige sessão autenticada. Sem `:current_scope`, redireciona para o login
  e interrompe o pipeline. Use depois de `fetch_current_scope/2`.
  """
  def require_authenticated(conn, _opts) do
    if conn.assigns[:current_scope] do
      conn
    else
      conn
      |> put_flash(:error, "Você precisa entrar para acessar esta página.")
      |> redirect(to: @login_path)
      |> halt()
    end
  end

  @doc """
  Callbacks de `on_mount` para LiveView:

    * `:mount_current_scope` — assina `:current_scope` (ou `nil`) e segue.
    * `:require_authenticated` — assina o scope e, sem login, redireciona para
      o login e interrompe a montagem.
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope do
      {:cont, socket}
    else
      socket =
        socket
        |> LiveView.put_flash(:error, "Você precisa entrar para acessar esta página.")
        |> LiveView.redirect(to: @login_path)

      {:halt, socket}
    end
  end

  # `assign_new` evita reconsultar o banco quando o LiveView remonta (HTTP →
  # WebSocket) com a mesma sessão.
  defp mount_current_scope(socket, session) do
    Component.assign_new(socket, :current_scope, fn -> resolve_scope(session) end)
  end

  defp scope_from(conn), do: resolve_scope(conn)

  defp resolve_scope(conn_or_session) do
    case Maraca.get_session_user(conn_or_session) do
      {:ok, ava} -> Scope.for_ava(ava)
      {:error, :not_authenticated} -> nil
    end
  end
end
