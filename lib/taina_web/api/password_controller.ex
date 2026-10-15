defmodule TainaWeb.API.PasswordController do
  @moduledoc """
  A redefinicao de senha pelo app (RFC_005 secao 12): o deep link do box carrega
  o token, e o app consulta o estado e define a senha nova por aqui, sem passar
  pela web.

  Sem `password_confirmation` de proposito, igual ao aceite do convite: quem
  confere as duas senhas e o proprio app, e o kernel trataria a divergencia
  como token invalido.
  """

  use TainaWeb, :controller

  alias Taina.Maraca
  alias Taina.Scope
  alias TainaWeb.API.Error
  alias TainaWeb.API.Params
  alias TainaWeb.API.Serializer

  def show(conn, %{"token" => token}) do
    case Maraca.reset_status(token) do
      :ok -> json(conn, %{"valid" => true})
      :invalid -> Error.reply(conn, :invalid_token)
    end
  end

  def update(conn, %{"token" => token} = params) do
    password = params["password"]

    with {:ok, ava} <- Maraca.reset_password(token, password, password),
         {:ok, tekoa} <- Maraca.get_tekoa(),
         scope = Scope.new(ava, tekoa),
         {:ok, %{device: device, token: raw}} <-
           Maraca.create_device_token(scope, Params.device_name(params)) do
      conn
      |> put_status(201)
      |> json(Serializer.session(raw, device, scope))
    else
      {:error, reason} -> Error.reply(conn, reason)
    end
  end
end
