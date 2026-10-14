defmodule TainaWeb.API.Auth do
  @moduledoc """
  Autenticacao da API por token de dispositivo (RFC_005 secao 5): plug de
  funcao, espelha `TainaWeb.Auth` sem toca-lo.

  Le `Authorization: Bearer <tnd_...>`, resolve em `Taina.Scope` e assina
  `:current_scope` e `:api_device`. A API nunca le a sessao de cookie, entao nao
  ha CSRF a modelar.
  """

  import Plug.Conn

  alias Taina.Maraca
  alias TainaWeb.API.Error

  @doc "Le o Bearer e, quando vale, assina o scope e o dispositivo. Nao barra ninguem."
  def fetch_api_scope(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{scope: scope, device: device}} <- Maraca.resolve_device_token(token) do
      conn
      |> assign(:current_scope, scope)
      |> assign(:api_device, device)
    else
      _ -> conn
    end
  end

  @doc "Sem scope, responde 401 no envelope."
  def require_api_auth(conn, _opts) do
    if conn.assigns[:current_scope] do
      conn
    else
      conn |> Error.reply(:not_authenticated) |> halt()
    end
  end

  @doc """
  Sem zelador, responde 403. A API e contrato documentado: diverge do 404 do
  painel web de proposito, porque o cliente precisa distinguir proibido de
  inexistente.
  """
  def require_api_zelador(conn, _opts) do
    case conn.assigns[:current_scope] do
      %{ava: ava} -> if Maraca.zelador?(ava), do: conn, else: forbidden(conn)
      _ -> forbidden(conn)
    end
  end

  defp forbidden(conn), do: conn |> Error.reply(:not_zelador) |> halt()
end
