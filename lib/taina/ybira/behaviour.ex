defmodule Taina.Ybira.Behaviour do
  @moduledoc """
  Contrato público do Ybira, o sistema de arquivos da comunidade.

  Espelha o padrão de `Taina.Maraca.Behaviour`: toda a documentação de regra de
  negócio vive aqui (nos `@callback`); `Taina.Ybira` implementa com `@impl true`.
  Ter o contrato isolado permite trocar a implementação por um mock em testes e
  documenta a fronteira do contexto num só lugar.

  Toda função recebe um `Taina.Scope` (quem + qual Tekoa) e roda sob isolamento
  RLS, exceto `purge_deleted_files/1`, operação de sistema que cruza Tekoas.
  """

  alias Taina.Scope
  alias Taina.Ybira.File
  alias Taina.Ybira.Folder

  @typedoc "Página de uma listagem por cursor: itens + cursor opaco da próxima página (`nil` no fim)."
  @type page(item) :: %{items: [item], next_cursor: binary | nil}

  @doc """
  Faz upload de um arquivo a partir de um caminho temporário.

  ## Regras de Negócio

  - O MIME é detectado pelos *magic bytes* do conteúdo, não pela extensão
  - Tipos fora da allowlist (inclui executáveis) são rejeitados com
    `{:error, :mime_not_allowed}`
  - A cota da Tekoa é verificada; estouro vira `{:error, :storage_quota_exceeded}`
  - Cota e inserção acontecem na mesma transação; em erro, os bytes copiados são
    removidos do disco

  ## Opções

    * `:filename` - nome original (default: basename do caminho)
    * `:folder_id` - id interno da pasta de destino (default: raiz)

  ## Retorno

    * `{:ok, %File{}}` - arquivo salvo
    * `{:error, :mime_not_allowed | :storage_quota_exceeded | term}`
  """
  @callback upload(Scope.t(), Path.t(), keyword) :: {:ok, File.t()} | {:error, term}

  @doc """
  Busca um arquivo (não deletado) pelo `public_id`, dentro da Tekoa do scope.

  Aplica a regra de leitura das duas zonas: a casa de outro morador (sem
  permissão explícita) volta `{:error, :forbidden}`, distinto de
  `{:error, :not_found}` (o arquivo não existe nessa Tekoa).
  """
  @callback get_file(Scope.t(), String.t()) :: {:ok, File.t()} | {:error, :not_found | :forbidden}

  @doc """
  Lista arquivos não-deletados de uma pasta (`public_id`) ou da raiz (`nil`),
  mais novos primeiro, paginados por cursor.

  ## Opções

    * `:limit` - itens por página (default: 50)
    * `:after_cursor` - cursor opaco devolvido em `next_cursor`
  """
  @callback list_files(Scope.t(), String.t() | nil, keyword) :: {:ok, page(File.t())}

  @doc """
  Move um arquivo para a lixeira (soft delete). Apenas o dono pode deletar.

  Os bytes ficam no disco e a cota não muda; o `PurgeTrash` reclama o espaço
  depois de 30 dias. `restore_file/2` desfaz nesse meio-tempo.
  """
  @callback delete_file(Scope.t(), String.t()) :: {:ok, File.t()} | {:error, :not_found}

  @doc """
  Restaura um arquivo da lixeira (limpa `deleted_at`). Apenas o dono (o zelador
  não tem atalho: pede via `Maraca.request_access/5` e o dono aprova).
  """
  @callback restore_file(Scope.t(), String.t()) :: {:ok, File.t()} | {:error, :not_found}

  @doc """
  Lista os arquivos do scope que estão na lixeira, paginados (ver `list_files/3`).
  """
  @callback list_trash(Scope.t(), keyword) :: {:ok, page(File.t())}

  @doc """
  Renomeia um arquivo (muda só o `original_filename`; os bytes e o nome no disco
  ficam). Apenas o dono.
  """
  @callback rename_file(Scope.t(), String.t(), String.t()) ::
              {:ok, File.t()} | {:error, :not_found | Ecto.Changeset.t()}

  @doc """
  Move um arquivo para outra pasta (`public_id`) ou para a raiz (`nil`). Apenas
  o dono.
  """
  @callback move_file(Scope.t(), String.t(), String.t() | nil) ::
              {:ok, File.t()} | {:error, :not_found}

  @doc """
  Publica um arquivo na praca (casa -> praca, RFC_003 D1): torna-o legivel por
  todo morador. Apenas o dono (o zelador nao tem atalho). Reversivel via
  `tirar_file_da_praca/2`. Idempotente. Nao cascateia para pastas.
  """
  @callback publicar_file(Scope.t(), String.t()) :: {:ok, File.t()} | {:error, :not_found}

  @doc """
  Tira um arquivo da praca (praca -> casa): volta a ser privado, so o dono e
  quem tem permissao explicita le. Apenas o dono. Idempotente.
  """
  @callback tirar_file_da_praca(Scope.t(), String.t()) :: {:ok, File.t()} | {:error, :not_found}

  @doc """
  Cria uma pasta. `attrs` aceita `:name` e, opcionalmente, `:parent_public_id`
  (a pasta-pai; `nil` cria na raiz). `parent_public_id` inexistente vira
  `{:error, :not_found}`.
  """
  @callback create_folder(Scope.t(), map) ::
              {:ok, Folder.t()} | {:error, :not_found | Ecto.Changeset.t()}

  @doc """
  Busca uma pasta (não deletada) pelo `public_id`.

  Aplica a regra de leitura das duas zonas: a casa de outro morador (sem
  permissão explícita) volta `{:error, :forbidden}`, distinto de
  `{:error, :not_found}` (a pasta não existe nessa Tekoa).
  """
  @callback get_folder(Scope.t(), String.t()) :: {:ok, Folder.t()} | {:error, :not_found | :forbidden}

  @doc """
  Renomeia uma pasta. Apenas o dono.
  """
  @callback rename_folder(Scope.t(), String.t(), String.t()) ::
              {:ok, Folder.t()} | {:error, :not_found | Ecto.Changeset.t()}

  @doc """
  Move uma pasta para baixo de outra (`public_id`) ou para a raiz (`nil`). Apenas
  o dono. Rejeita ciclos (mover para si mesma ou para uma descendente) com
  `{:error, :circular_reference}`.
  """
  @callback move_folder(Scope.t(), String.t(), String.t() | nil) ::
              {:ok, Folder.t()} | {:error, :not_found | :circular_reference | Ecto.Changeset.t()}

  @doc """
  Deleta uma pasta em cascata (soft delete): a pasta, os arquivos dentro dela e
  as subpastas, recursivamente. Apenas o dono. Não devolve cota, quem faz isso
  é o `PurgeTrash`.
  """
  @callback delete_folder(Scope.t(), String.t()) :: {:ok, :deleted} | {:error, :not_found}

  @doc """
  Publica uma pasta na praca (casa -> praca): a *listagem da propria pasta* passa
  a ser legivel por todo morador. **Nao cascateia** para os filhos (RFC_003 D1);
  cada arquivo/subpasta carrega a propria zona. Apenas o dono. Idempotente.
  """
  @callback publicar_folder(Scope.t(), String.t()) :: {:ok, Folder.t()} | {:error, :not_found}

  @doc """
  Tira uma pasta da praca (praca -> casa). Apenas o dono. Idempotente.
  """
  @callback tirar_folder_da_praca(Scope.t(), String.t()) :: {:ok, Folder.t()} | {:error, :not_found}

  @doc """
  Lista o conteúdo de uma pasta (`public_id`) ou da raiz (`nil`): subpastas (todas)
  e arquivos não-deletados (paginados por offset; `next_cursor` é o próximo
  offset, ou `nil` no fim).

  ## Opções

    * `:sort` - `{campo, direção}`, campo em `:name | :date | :size`, direção em
      `:asc | :desc` (default `{:date, :desc}`)
    * `:limit` - itens por página (default: 50)
    * `:offset` - deslocamento da página (default: 0)
  """
  @callback list_folder_contents(Scope.t(), String.t() | nil, keyword) ::
              {:ok, %{folders: [Folder.t()], files: [File.t()], next_cursor: non_neg_integer | nil}}
              | {:error, :not_found}

  @doc """
  Lista todas as pastas (não deletadas) da Tekoa do scope, em ordem alfabética,
  base do seletor de destino de "Mover para...".
  """
  @callback list_folders(Scope.t()) :: {:ok, [Folder.t()]}

  @doc """
  Verifica se a Tekoa do scope comporta mais `byte_size` bytes.
  """
  @callback check_capacity(Scope.t(), pos_integer) :: :ok | {:error, :storage_quota_exceeded}

  @doc """
  Devolve uso e cota de armazenamento da Tekoa do scope.
  """
  @callback storage_stats(Scope.t()) ::
              {:ok, %{used_bytes: integer, quota_bytes: integer | nil}}

  @doc """
  Apaga de vez (banco + disco) os arquivos na lixeira com `deleted_at` anterior a
  `cutoff`, devolvendo a cota, e remove também as pastas na lixeira (que só
  guardam metadados). Operação de **sistema** (`skip_tekoa_id: true`, cruza
  todas as Tekoas), usada pelo worker `PurgeTrash`. Devolve
  `{:ok, qtd_arquivos_apagados}`.
  """
  @callback purge_deleted_files(DateTime.t()) :: {:ok, non_neg_integer}

  @doc """
  Últimos arquivos enviados (qualquer pasta, fora da lixeira), mais novos
  primeiro, a lista "Recentes" da home. `opts`: `:limit` (padrão 4).
  """
  @callback list_recent(Scope.t(), keyword) :: {:ok, [File.t()]}

  @doc """
  Conta os arquivos ativos (fora da lixeira) da Tekoa do scope, card
  "Arquivos" da home.
  """
  @callback count_files(Scope.t()) :: {:ok, non_neg_integer}

  @doc """
  Conta as fotos ativas (`mime_type image/*`, fora da lixeira), card "Fotos"
  da home.
  """
  @callback count_photos(Scope.t()) :: {:ok, non_neg_integer}

  @doc """
  Uso de armazenamento por categoria de mídia (tela "Armazenamento" e card da
  home desktop): bytes somados de arquivos ativos, agrupados em `:photos`,
  `:videos`, `:documents` e `:others`.
  """
  @callback storage_stats_by_kind(Scope.t()) ::
              {:ok,
               %{photos: non_neg_integer, videos: non_neg_integer, documents: non_neg_integer, others: non_neg_integer}}
end
