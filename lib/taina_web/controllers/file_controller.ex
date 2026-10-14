defmodule TainaWeb.FileController do
  @moduledoc """
  Download e miniatura de arquivos do Ybira na web.

  Autenticacao por sessao (cookie do Phoenix): a pipeline `:authenticated` faz
  `fetch_session` e `Maraca.get_session_user/1` resolve o Ava + a Tekoa, de onde
  montamos o `Scope`. Os bytes saem pelo `TainaWeb.FileServing`, o mesmo da API;
  aqui so ficam a auth por sessao e o redirect das telas.
  """

  use TainaWeb, :controller

  alias Taina.Maraca
  alias Taina.Scope
  alias Taina.Ybira
  alias TainaWeb.FileServing

  def download(conn, %{"rkey" => rkey}) do
    with {:ok, ava} <- Maraca.get_session_user(conn),
         scope = Scope.for_ava(ava),
         {:ok, file} <- Ybira.get_file(scope, rkey),
         {:ok, path} <- Ybira.blob_path(file) do
      FileServing.serve(conn, file, path)
    else
      # Casa de outra pessoa: o navegador recebe uma pagina, nao um 403 vazio.
      # A tela do arquivo e que mostra o porque e o caminho (Pedir acesso).
      {:error, :forbidden} -> redirect(conn, to: ~p"/arquivos/#{rkey}")
      {:error, :not_authenticated} -> redirect(conn, to: ~p"/login")
      {:error, :not_found} -> send_resp(conn, 404, "")
    end
  end

  def thumbnail(conn, %{"rkey" => rkey, "size" => size}) do
    with {:ok, ava} <- Maraca.get_session_user(conn),
         scope = Scope.for_ava(ava),
         {:ok, file} <- Ybira.get_file(scope, rkey),
         {:ok, metadata} <- Ybira.photo_metadata(scope, file) do
      FileServing.thumbnail(conn, metadata, size)
    else
      # Mesma regra do download: sem pagina em branco; quem nao pode ler o
      # arquivo e levado a tela dele (Pedir acesso).
      {:error, :forbidden} -> redirect(conn, to: ~p"/arquivos/#{rkey}")
      {:error, :not_authenticated} -> redirect(conn, to: ~p"/login")
      _ -> send_resp(conn, 404, "")
    end
  end
end
