defmodule Taina.Nhaman.Update do
  @moduledoc """
  Status de atualização da caixa (tela "Saúde da comunidade", RFC_003 seção 6):
  a versão que está rodando contra a mais recente publicada.

  ## Soberania: a verificação é opt-in e desligada por padrão

  O RFC_003 (D6) manda a caixa ser soberana, "nunca telefonar para casa". O
  princípio nasceu para telemetria e dados da comunidade, que nunca saem; mas
  "qual é a última versão publicada" só existe na internet, nos releases do
  GitHub. O corte conservador: a pergunta só é feita quando quem opera a caixa
  liga explicitamente (`TAINA_UPDATE_CHECK=true`, default off), e a pergunta
  é só a pergunta. Um GET sem corpo, sem identificador, sem dado da comunidade,
  sem nome da Tekoa, sem contagem de moradores: nada além da URL pública dos
  releases. Uma caixa que não pediu não conversa com ninguém, e quando pede
  não diz quem é.

  A tela é honesta com isso: verificação desligada é dita como estado ("a
  caixa não conversa com a internet por conta própria"), nunca fingida de
  "atualizado".
  """

  @releases_url "https://api.github.com/repos/taina-labs/taina/releases/latest"
  @receive_timeout 3_000

  @doc """
  O estado de atualização para a tela de saúde.

  ## Retorno

    * `%{running: versão, result: :check_off}` - verificação desligada (o
      default soberano)
    * `%{running: versão, result: :up_to_date}` - a caixa está na última
    * `%{running: versão, result: {:update_available, latest}}` - existe mais
      nova que a que roda
    * `%{running: versão, result: :unavailable}` - a pergunta foi feita e não
      teve resposta agora
    * `%{running: versão, result: :unknown}` - alguma das versões não deu
      para comparar

  `opts`: `:releases_url` (injetável em teste, default a config/constante).
  """
  def status(opts \\ []) do
    running = running_version()

    result =
      if enabled?() do
        case latest_release(opts) do
          {:ok, latest} -> compare(running, latest)
          :error -> :unavailable
        end
      else
        :check_off
      end

    %{running: running, result: result}
  end

  @doc "A verificação está ligada? (`config :taina, :update_check, enabled:`, default off)."
  def enabled?, do: Keyword.get(config(), :enabled, false)

  @doc "A versão que está rodando nesta caixa (a do build, `Application.spec/2`)."
  def running_version do
    case Application.spec(:taina, :vsn) do
      nil -> "desconhecida"
      vsn -> to_string(vsn)
    end
  end

  @doc ~s{Normaliza a tag de release do GitHub (`"v0.2.0"` -> `"0.2.0"`).}
  def normalize_version("v" <> rest), do: String.trim(rest)
  def normalize_version(other), do: String.trim(other)

  @doc """
  Compara a versão rodando com a última publicada.

  `:unknown` quando alguma das duas não é um `Version` válido: a tela diz
  que não deu para comparar, não inventa resposta.
  """
  def compare(running, latest) do
    case {Version.parse(running), Version.parse(latest)} do
      {{:ok, running_v}, {:ok, latest_v}} ->
        if Version.compare(running_v, latest_v) in [:eq, :gt] do
          :up_to_date
        else
          {:update_available, latest}
        end

      _other ->
        :unknown
    end
  end

  # A única coisa que sai da caixa é a própria pergunta (ver o moduledoc): GET
  # sem corpo e sem header de identificação, resposta curta ou nada. Exceção
  # (URL mal configurada e afins) vira :error, a tela nunca cai por causa da
  # pergunta opcional.
  defp latest_release(opts) do
    url = Keyword.get(opts, :releases_url) || releases_url()

    case Req.get(url, receive_timeout: @receive_timeout) do
      {:ok, %Req.Response{status: 200, body: %{"tag_name" => tag}}} when is_binary(tag) ->
        {:ok, normalize_version(tag)}

      _other ->
        :error
    end
  rescue
    _exception -> :error
  end

  defp releases_url, do: Keyword.get(config(), :url, @releases_url)

  defp config, do: Application.get_env(:taina, :update_check, [])
end
