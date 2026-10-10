defmodule TainaWeb.InviteController do
  @moduledoc """
  Aceite de convite: o `InviteAcceptLive` valida o formulário ao vivo e o
  submit final chega como POST tradicional, `accept_invite/2` cria a conta
  e a sessão nasce na mesma requisição.
  """

  use TainaWeb, :controller

  alias Ecto.Changeset
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
        |> put_flash(:error, gettext("Este convite expirou ou já foi usado. Peça um novo link a quem te convidou."))
        |> redirect(to: ~p"/login")

      {:error, changeset} ->
        conn
        |> put_flash(:error, accept_error_message(changeset))
        |> redirect(to: ~p"/convite/#{token}?#{non_secret_query(params)}")
    end
  end

  # Volta para a tela de aceite preservando só campos não secretos: a pessoa
  # não redigita tudo e a senha nunca viaja na URL.
  defp non_secret_query(params) do
    params
    |> Map.take(["username", "display_name"])
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
  end

  # Tradução do changeset para a frase do campo com problema (o LiveView não
  # recebe o changeset, então a mensagem viaja no flash).
  defp accept_error_message(%Changeset{} = changeset) do
    cond do
      confirmation_mismatch?(changeset) -> gettext("As duas senhas não são iguais.")
      username_taken?(changeset) -> gettext("Esse nome de usuário já existe. Escolha outro.")
      true -> gettext("Não foi possível criar a conta. Revise os dados e tente de novo.")
    end
  end

  defp accept_error_message(_other) do
    gettext("Não foi possível criar a conta. Revise os dados e tente de novo.")
  end

  defp confirmation_mismatch?(%Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {:password, {_message, opts}} -> Keyword.get(opts, :validation) == :confirmation
      _other -> false
    end)
  end

  defp username_taken?(%Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {:username, {_message, opts}} -> Keyword.get(opts, :constraint) == :unique
      _other -> false
    end)
  end
end
