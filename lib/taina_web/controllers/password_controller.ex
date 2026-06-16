defmodule TainaWeb.PasswordController do
  @moduledoc """
  Consome o link de redefinição que o zelador gerou: a pessoa define a senha
  nova e a sessão nasce na mesma requisição (LiveView não escreve cookie). O
  token só é validado de verdade aqui, no submit.
  """

  use TainaWeb, :controller

  alias Taina.Maraca

  def update(conn, %{"token" => token, "account" => params}) do
    case Maraca.reset_password(token, params["password"], params["password_confirmation"]) do
      {:ok, ava} ->
        conn
        |> TainaWeb.Auth.log_in(ava)
        |> put_flash(:info, gettext("Senha redefinida. Você já está dentro."))
        |> redirect(to: ~p"/")

      {:error, :invalid_token} ->
        conn
        |> put_flash(:error, gettext("Este link expirou ou já foi usado. Peça um novo a quem cuida da comunidade."))
        |> redirect(to: ~p"/login")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, gettext("Não foi possível redefinir a senha. Revise os dados e tente de novo."))
        |> redirect(to: ~p"/redefinir/#{token}")
    end
  end
end
