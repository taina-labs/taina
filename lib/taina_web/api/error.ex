defmodule TainaWeb.API.Error do
  @moduledoc """
  O envelope unico de erro da API (RFC_005 D6): `{"error": {"code", "message",
  "details?"}}`.

  O `code` e o motivo do contexto em string, o vocabulario estavel do cliente;
  o status HTTP vem de `Ypy.Wire.Errors`, a mesma tabela que o kernel usa, entao
  a API e o kernel falam os mesmos motivos. A `message` e pt-BR, curta, com
  saida e sem culpa.

  A mensagem nao passa por gettext de proposito: quem decide o que mostrar e o
  `code`, e esta string e o fallback legivel de quem inspeciona a resposta crua.
  O motivo de um 500 vai para o log, nunca para o corpo.
  """

  import Plug.Conn

  alias Ypy.Wire.Errors

  require Logger

  @messages %{
    "not_authenticated" => "Entre para continuar.",
    "invalid_credentials" => "Usuário ou senha incorretos.",
    "invalid_token" => "Este link não vale mais. Peça um novo a quem cuida da comunidade.",
    "account_deactivated" => "Esta conta está desativada.",
    "forbidden" => "Você não tem acesso a este conteúdo.",
    "unauthorized" => "Você não pode fazer isso.",
    "not_zelador" => "Só quem cuida da comunidade pode fazer isso.",
    "not_owner" => "Só quem guardou pode mudar isso.",
    "not_authorized" => "Você não tem acesso a este conteúdo.",
    "not_found" => "Não encontramos isso aqui.",
    "no_folder" => "Este arquivo não está em nenhuma pasta.",
    "last_zelador" => "Não dá para deixar a comunidade sem ninguém para cuidar dela.",
    "not_pending" => "Este convite já foi usado.",
    "invalid_status" => "Este pedido já foi decidido.",
    "already_has_access" => "Esta pessoa já tem acesso.",
    "already_readable" => "Você já pode ler este arquivo.",
    "already_bootstrapped" => "Esta comunidade já foi criada.",
    "not_bootstrapped" => "Esta comunidade ainda não foi criada.",
    "circular_reference" => "Não dá para mover uma pasta para dentro dela mesma.",
    "storage_quota_exceeded" => "O espaço da comunidade acabou. Libere arquivos ou peça mais espaço.",
    "cannot_request_own" => "Este arquivo já é seu.",
    "cross_tekoa_owner" => "Este conteúdo é de outra comunidade.",
    "invalid_action" => "Essa ação não vale aqui.",
    "mime_not_allowed" => "Este tipo de arquivo não é aceito.",
    "missing_file" => "Nenhum arquivo foi enviado.",
    "rate_limited" => "Muitas tentativas seguidas. Espere um pouco.",
    "validation_failed" => "Confira os campos e tente de novo.",
    "internal_error" => "Algo falhou do nosso lado. Tente de novo."
  }

  @fallback_code "internal_error"

  @doc """
  Responde o motivo no envelope, com o status da tabela do fio. Um
  `%Ecto.Changeset{}` vira 422 `validation_failed` com os erros campo a campo
  em `details`.
  """
  @spec reply(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def reply(conn, reason) do
    {status, code} = Errors.resolve(reason)

    # O motivo de um 500 fica no log, para o operador; o corpo nao o carrega.
    if status >= 500, do: Logger.error("api: motivo nao mapeado #{inspect(reason)}")

    conn
    |> put_status(status)
    |> Phoenix.Controller.json(body(code, details(reason)))
  end

  defp body(code, nil), do: %{"error" => %{"code" => code, "message" => message(code)}}

  defp body(code, details) do
    %{"error" => %{"code" => code, "message" => message(code), "details" => details}}
  end

  defp message(code), do: Map.get(@messages, code, @messages[@fallback_code])

  # A mesma traducao que a web usa (`TainaWeb.CoreComponents.translate_error/1`):
  # o catalogo pt-BR do dominio `errors` cobre as mensagens do Ecto, e o que ja
  # vem em pt-BR do contexto (mensagens de constraint do kernel) passa intacto.
  defp details(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} -> translate(msg, opts) end)
  end

  defp details(_reason), do: nil

  defp translate(msg, opts) do
    if count = opts[:count] do
      Gettext.dngettext(TainaWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(TainaWeb.Gettext, "errors", msg, opts)
    end
  end
end
