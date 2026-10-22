defmodule TainaWeb.API.SessionController do
  @moduledoc """
  Login e logout por token de dispositivo (RFC_005 secao 9).

  O login reusa o rate limit de forca bruta da web e devolve o segredo cru uma
  unica vez; o logout revoga o dispositivo da propria chamada.
  """

  use TainaWeb, :controller

  alias Taina.Maraca
  alias Taina.Scope
  alias TainaWeb.API.Error
  alias TainaWeb.API.Params
  alias TainaWeb.API.Serializer

  def create(conn, params) do
    with {:ok, tekoa} <- Maraca.get_tekoa(),
         {:ok, ava} <- Maraca.authenticate(params["username"], params["password"], tekoa),
         scope = Scope.new(ava, tekoa),
         {:ok, %{device: device, token: token}} <-
           Maraca.create_device_token(scope, Params.device_name(params)) do
      conn
      |> put_status(201)
      |> json(Serializer.session(token, device, scope))
    else
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def delete(conn, _params) do
    scope = conn.assigns[:current_scope]
    device = conn.assigns[:api_device]

    case Maraca.revoke_device(scope, device.public_id) do
      {:ok, _device} -> send_resp(conn, 204, "")
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  @doc """
  A troca da propria senha (contrato review 0.1.0, C5): a senha atual confere,
  a nova entra, e os OUTROS aparelhos da pessoa perdem o token -- o da chamada
  fica, para nao derrubar quem acabou de trocar. A regra mora no contexto
  (`Maraca.revoke_other_devices/2`), compartilhada com a web e o shell.
  """
  def update_password(conn, params) do
    scope = conn.assigns[:current_scope]
    device = conn.assigns[:api_device]

    case Maraca.update_password(scope, params["current_password"], params["new_password"]) do
      {:ok, _ava} ->
        :ok = Maraca.revoke_other_devices(scope, except: device.public_id)
        json(conn, %{"ok" => true})

      # A senha atual errada e 403, nao 401: quem chama ja esta autenticado,
      # e 401 pediria login de novo (contrato review 0.1.0, C5).
      {:error, :invalid_credentials} ->
        Error.reply(conn, 403, "invalid_credentials")

      {:error, reason} ->
        Error.reply(conn, reason)
    end
  end
end
