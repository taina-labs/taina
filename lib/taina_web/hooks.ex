defmodule TainaWeb.Hooks do
  @moduledoc """
  `on_mount` compartilhado. `:shell` (telas autenticadas, com `current_scope`
  já atribuído pelo Auth): inscreve-se uma vez no tópico de eventos do Ava
  (RFC_003 D4) quando conectado; cada LiveView trata só as mensagens da sua
  tela e ignora o resto. A inscrição não fica ao vivo entre abas: cada
  mount/navegação refaz a sua.

  `:connection` (cascas de auth, spec 6.5): atribui `secure_connection?` a partir
  do URI da requisição; a decisão vive na função pura `secure_connection?/1`,
  o hook só atribui.
  """

  use TainaWeb, :verified_routes

  import Phoenix.LiveView, only: [connected?: 1, get_connect_info: 2]

  alias Taina.Maraca

  def on_mount(:shell, _params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) and scope, do: Maraca.subscribe_to_my_events(scope.ava)

    {:cont, socket}
  end

  # ---------- :connection (spec 5, secao 6.5) ----------

  # O hook só atribui: conectado, o URI vem do connect_info; no render morto,
  # do host_uri do socket. Valor ausente (ex.: connect info incompleto) é
  # conservador: assume segura, para nunca exibir o aviso sem prova.
  def on_mount(:connection, _params, _session, socket) do
    uri = if connected?(socket), do: get_connect_info(socket, :uri), else: Map.get(socket, :host_uri)
    {:cont, Phoenix.Component.assign(socket, :secure_connection?, secure_connection?(uri))}
  end

  @doc """
  Decisão pura de conexão segura (spec 6.5): https é seguro sempre; http em
  host de loopback (localhost, 127.0.0.1, ::1) é a própria máquina, seguro;
  http em qualquer outro host, inseguro. Sem URI, assume segura.
  """
  def secure_connection?(nil), do: true

  def secure_connection?(%URI{scheme: scheme, host: host}) do
    case {scheme, host} do
      {"https", _host} -> true
      {"http", "localhost"} -> true
      {"http", "127.0.0.1"} -> true
      {"http", "::1"} -> true
      {"http", _host} -> false
      _scheme -> true
    end
  end

  def secure_connection?(uri) when is_binary(uri), do: secure_connection?(URI.parse(uri))
end
