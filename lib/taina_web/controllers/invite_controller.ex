defmodule TainaWeb.InviteController do
  @moduledoc """
  Aceite de convite: o `InviteAcceptLive` valida o formulário ao vivo e o
  submit final chega como POST tradicional, `accept_invite/2` cria a conta
  e a sessão nasce na mesma requisição.
  """

  use TainaWeb, :controller

  alias Taina.Maraca

  def accept(conn, %{"token" => token, "account" => params}) do
    case Maraca.accept_invite(token, params) do
      {:ok, ava} ->
        conn
        |> TainaWeb.Auth.log_in(ava)
        |> put_flash(:info, gettext("Conta criada. Boas-vindas à comunidade!"))
        |> redirect(to: ~p"/")

      {:error, :invalid_token} ->
        conn
        |> put_flash(:error, gettext("Este convite expirou ou já foi usado. Peça um novo link."))
        |> redirect(to: ~p"/login")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, gettext("Não foi possível criar a conta. Revise os dados e tente de novo."))
        |> redirect(to: ~p"/convite/#{token}")
    end
  end
end
