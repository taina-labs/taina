defmodule TainaWeb.InviteCode do
  @moduledoc """
  Parser puro do "Convite colar" (spec 6.5, board
  88db615f-12f9-80b9-8008-d6329edbdcc6): aceita o link inteiro (com ou sem
  esquema, caminho `/convite/:token`) ou só o código.

  Com o host da requisição (`parse/2`), link apontado para outro host volta
  `{:error, :other_community}`: a web não troca de instância, quem chegou por
  um link de outra comunidade precisa abrir aquele link no navegador daquela
  caixa.
  """

  # O token é o mesmo alfabeto do link que o QR code abre: letras, números,
  # hífen e underscore.
  @token_format ~r/^[A-Za-z0-9_-]+$/

  # O link pode vir sem o esquema ("taina.local/convite/abc", como no
  # placeholder do board): o trecho antes do caminho é o host.
  @link_format ~r{^(?:[a-zA-Z][a-zA-Z0-9+.-]*://)?([^/?#\s]*)/convite/([A-Za-z0-9_-]+)/?$}

  @doc """
  `{:ok, token} | {:error, :invalid}` para o texto colado: link completo de
  qualquer host ou código cru.
  """
  @spec parse(term()) :: {:ok, String.t()} | {:error, :invalid}
  def parse(input), do: parse(input, nil)

  @doc """
  Com o host da requisição, link apontado para outro host volta
  `{:error, :other_community}`.
  """
  @spec parse(term(), String.t() | nil) ::
          {:ok, String.t()} | {:error, :invalid | :other_community}
  def parse(input, current_host) do
    case extract(String.trim(input || "")) do
      {:ok, token, nil} -> {:ok, token}
      {:ok, token, link_host} -> check_community(token, link_host, current_host)
      :error -> {:error, :invalid}
    end
  end

  # Sem host no texto colado (só o código), não há comunidade a conferir: o
  # aceite valida o token de qualquer jeito.
  defp check_community(token, _link_host, nil), do: {:ok, token}

  defp check_community(token, link_host, current_host) do
    if same_host?(link_host, current_host),
      do: {:ok, token},
      else: {:error, :other_community}
  end

  defp extract(""), do: :error

  defp extract(input) do
    if Regex.match?(@token_format, input) do
      {:ok, input, nil}
    else
      link(input)
    end
  end

  defp link(input) do
    case Regex.run(@link_format, input) do
      [_link, authority, token] -> {:ok, token, authority(authority)}
      nil -> :error
    end
  end

  # Caminho relativo ("/convite/abc") não aponta para outra comunidade.
  defp authority(""), do: nil
  defp authority(authority), do: authority

  # O host do link e o da requisição, sem porta nem caixa.
  defp same_host?(link_host, current_host) do
    normalize_host(link_host) == normalize_host(current_host)
  end

  defp normalize_host(host) do
    host |> String.downcase() |> String.split(":") |> List.first()
  end
end
