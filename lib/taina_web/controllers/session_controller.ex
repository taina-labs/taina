defmodule TainaWeb.SessionController do
  @moduledoc """
  Cria e destrói a sessão (cookie). LiveView não escreve cookie, então o login
  é um POST tradicional vindo do form do `LoginLive`; o resto da navegação
  segue live.
  """

  use TainaWeb, :controller

  alias Taina.Maraca

  def create(conn, %{"username" => username, "password" => password}) do
    with {:ok, tekoa} <- Maraca.get_tekoa(),
         {:ok, ava} <- Maraca.authenticate(username, password, tekoa) do
      conn
      |> TainaWeb.Auth.log_in(ava)
      |> redirect(to: ~p"/")
    else
      {:error, :not_bootstrapped} ->
        redirect(conn, to: ~p"/setup")

      {:error, _reason} ->
        conn
        |> put_flash(:error, gettext("Nome ou senha incorretos."))
        |> redirect(to: ~p"/login")
    end
  end

  # POST sem os campos esperados (form adulterado, bot): trata como credencial
  # invalida em vez de estourar FunctionClauseError (500).
  def create(conn, _params) do
    conn
    |> put_flash(:error, gettext("Nome ou senha incorretos."))
    |> redirect(to: ~p"/login")
  end

  def delete(conn, _params) do
    conn
    |> Maraca.destroy_session()
    |> put_flash(:info, gettext("Até logo!"))
    |> redirect(to: ~p"/login")
  end
end
