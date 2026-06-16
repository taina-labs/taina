defmodule TainaWeb.SetupController do
  @moduledoc """
  Passo final do wizard de primeiro boot: o `SetupLive` coleta os dados nos
  três passos e o submit final chega aqui como POST tradicional, `bootstrap/2`
  + login na mesma requisição (LiveView não escreve cookie de sessão).
  """

  use TainaWeb, :controller

  alias Taina.Maraca

  # Cota inicial = espaço livre do disco do storage (melhor esforço); sem leitura
  # possível, cai num padrão de 256 GB. O zelador reajusta depois em /armazenamento.
  @default_quota_bytes 256 * 1024 * 1024 * 1024

  def create(conn, %{"setup" => params}) do
    tekoa_attrs = %{name: params["community_name"], storage_quota_bytes: initial_quota_bytes()}

    zelador_attrs = %{
      username: params["username"],
      display_name: params["display_name"],
      password: params["password"],
      password_confirmation: params["password_confirmation"]
    }

    case Maraca.bootstrap(tekoa_attrs, zelador_attrs) do
      {:ok, %{ava: ava}} ->
        conn
        |> TainaWeb.Auth.log_in(ava)
        |> put_flash(:info, gettext("Sua nuvem está pronta. Boas-vindas!"))
        |> redirect(to: ~p"/")

      {:error, :already_bootstrapped} ->
        redirect(conn, to: ~p"/login")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, gettext("Não foi possível criar a comunidade. Revise os dados e tente de novo."))
        |> redirect(to: ~p"/setup")
    end
  end

  # POST sem o mapa "setup" (form adulterado, bot): pede revisao dos dados em
  # vez de estourar FunctionClauseError (500).
  def create(conn, _params) do
    conn
    |> put_flash(:error, gettext("Não foi possível criar a comunidade. Revise os dados e tente de novo."))
    |> redirect(to: ~p"/setup")
  end

  defp initial_quota_bytes do
    storage_root = Application.fetch_env!(:taina, :storage_root)

    with {out, 0} <- System.cmd("df", ["-k", storage_root], stderr_to_stdout: true),
         [_header, line | _rest] <- String.split(out, "\n"),
         [_fs, _blocks, _used, avail | _] <- String.split(line, ~r/\s+/, trim: true),
         {kbytes, ""} <- Integer.parse(avail) do
      kbytes * 1024
    else
      _ -> @default_quota_bytes
    end
  rescue
    _e in ErlangError -> @default_quota_bytes
  end
end
