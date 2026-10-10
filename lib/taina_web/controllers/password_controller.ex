defmodule TainaWeb.PasswordController do
  @moduledoc """
  Consome o link de redefinição que o zelador gerou: a pessoa define a senha
  nova e a sessão nasce na mesma requisição (LiveView não escreve cookie). O
  token só é validado de verdade aqui, no submit.
  """

  use TainaWeb, :controller

  alias Ecto.Changeset
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

      {:error, changeset} ->
        conn
        |> put_flash(:error, reset_error_message(changeset))
        |> redirect(to: ~p"/redefinir/#{token}")
    end
  end

  # Tradução do changeset para a frase do campo com problema (o LiveView não
  # recebe o changeset, então a mensagem viaja no flash).
  defp reset_error_message(%Changeset{} = changeset) do
    if confirmation_mismatch?(changeset) do
      gettext("As duas senhas não são iguais.")
    else
      gettext("Não foi possível redefinir a senha. Revise os dados e tente de novo.")
    end
  end

  defp reset_error_message(_other) do
    gettext("Não foi possível redefinir a senha. Revise os dados e tente de novo.")
  end

  defp confirmation_mismatch?(%Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {:password, {_message, opts}} -> Keyword.get(opts, :validation) == :confirmation
      _other -> false
    end)
  end
end
