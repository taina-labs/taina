defmodule TainaWeb.API.InviteController do
  @moduledoc """
  O convite pelo app (RFC_005 secao 12): o deep link do box carrega o token, e
  o app consulta o estado e aceita o convite por aqui, sem passar pela web.

  Sem `password_confirmation` de proposito: quem confere as duas senhas e o
  proprio app. Passar a confirmacao junto trataria a divergencia como token
  invalido (o kernel so ve um erro la), o 401 errado para um erro de digitacao.
  """

  use TainaWeb, :controller

  alias Taina.Maraca
  alias Taina.Scope
  alias TainaWeb.API.Error
  alias TainaWeb.API.Params
  alias TainaWeb.API.Serializer

  def show(conn, %{"token" => token}) do
    case Maraca.invite_status(token) do
      :ok -> json(conn, %{"valid" => true})
      :invalid -> Error.reply(conn, :invalid_token)
    end
  end

  def accept(conn, %{"token" => token} = params) do
    with {:ok, ava} <- Maraca.accept_invite(token, accept_attrs(params)),
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

  # So o que o cliente mandou de verdade: um display_name ausente nao pode
  # sobrescrever o default do changeset com nil.
  defp accept_attrs(params) do
    params
    |> Map.take(["username", "password", "display_name"])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
