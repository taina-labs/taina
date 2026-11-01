defmodule TainaWeb.SetupController do
  @moduledoc """
  Passo final do wizard de primeiro boot: o `SetupLive` coleta os dados nos
  três passos e o submit final chega aqui como POST tradicional, `bootstrap/2`
  + login na mesma requisição (LiveView não escreve cookie).

  O limite de armazenamento vem do passo 3 (spec 11.3): "inteiro" deixa a
  cota sem limite (`storage_quota_bytes: nil`, o disco inteiro) e "limite"
  traz um número de GB, validado como inteiro positivo e dentro do tamanho do
  disco; escolha inválida volta ao passo 3 com o aviso do campo. O antigo
  padrão "cota = espaço livre do disco" foi embora: quem quiser limite
  diferente ajusta depois em /armazenamento.
  """

  use TainaWeb, :controller

  alias Taina.Maraca
  alias TainaWeb.Disk

  @gigabyte 1024 * 1024 * 1024

  def create(conn, %{"setup" => params}) do
    case parse_quota(params, Disk.total_bytes()) do
      {:ok, storage_quota_bytes} ->
        tekoa_attrs = %{name: params["community_name"], storage_quota_bytes: storage_quota_bytes}

        zelador_attrs = %{
          username: params["username"],
          display_name: params["display_name"],
          password: params["password"]
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

      {:error, message} ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: ~p"/setup?passo=3")
    end
  end

  # POST sem o mapa "setup" (form adulterado, bot): pede revisao dos dados em
  # vez de estourar FunctionClauseError (500).
  def create(conn, _params) do
    conn
    |> put_flash(:error, gettext("Não foi possível criar a comunidade. Revise os dados e tente de novo."))
    |> redirect(to: ~p"/setup")
  end

  @doc """
  Parser puro da escolha de limite do passo 3 (spec 11.3): "inteiro" escolhe
  o disco inteiro (`{:ok, nil}`); "limite" traz um número de GB, inteiro e
  positivo, no máximo o tamanho do disco (quando ele é conhecido). Fora
  disso, `{:error, mensagem}` com a copy do campo, para o POST fora do
  wizard voltar ao passo 3 com o mesmo aviso que o LiveView espelha.
  """
  def parse_quota(%{"storage_quota" => "inteiro"} = _params, _disk_size), do: {:ok, nil}

  def parse_quota(%{"storage_quota" => "limite", "quota_gb" => gb} = _params, disk_size) do
    with {:ok, bytes} <- gb_to_bytes(gb),
         :ok <- within_disk?(bytes, disk_size) do
      {:ok, bytes}
    end
  end

  # Sem a escolha (form antigo, adulterado), não há limite para inferir.
  def parse_quota(_params, _disk_size) do
    {:error, gettext("Escolha o limite: o disco inteiro ou um número de GB.")}
  end

  defp gb_to_bytes(gb) when is_binary(gb) do
    case Integer.parse(gb) do
      {n, ""} when n > 0 -> {:ok, n * @gigabyte}
      _other -> {:error, quota_invalid_message()}
    end
  end

  defp gb_to_bytes(_other), do: {:error, quota_invalid_message()}

  defp quota_invalid_message do
    gettext("O limite precisa ser um número de GB maior que zero.")
  end

  # Sem o tamanho do disco (leitura falhou), a checagem de teto passa: cota
  # maior que o disco não quebra nada, o disco enche primeiro.
  defp within_disk?(_bytes, nil), do: :ok
  defp within_disk?(bytes, disk_size) when bytes <= disk_size, do: :ok

  defp within_disk?(_bytes, disk_size) do
    {:error, gettext("O disco tem %{gb} GB. Escolha um limite menor.", gb: div(disk_size, @gigabyte))}
  end
end
