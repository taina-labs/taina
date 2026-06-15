defmodule Taina.Jaci.Behaviour do
  @moduledoc """
  Contrato público do Jaci-lite, a galeria de fotos da comunidade.

  Jaci é uma camada de **leitura** sobre o Ybira (RFC 002, D4): ele consulta as
  imagens (`mime_type image/*`) que o Ybira guarda e as apresenta como grade e
  linha do tempo. Não armazena nada próprio, não muta arquivos, quem faz upload,
  thumbnail e soft delete é o Ybira. Composição, não herança.

  Espelha o padrão de `Taina.Ybira.Behaviour`: as regras de negócio vivem aqui
  (nos `@callback`); `Taina.Jaci` implementa com `@impl true`. Toda função recebe
  um `Taina.Scope` e roda sob isolamento RLS.
  """

  alias Taina.Jaci.Timeline
  alias Taina.Scope
  alias Taina.Ybira.File

  @typedoc "Página de fotos por cursor: itens + cursor opaco da próxima página (`nil` no fim)."
  @type photo_page :: %{items: [File.t()], next_cursor: binary | nil}

  @typedoc "Página da linha do tempo: dias agrupados + cursor da próxima página."
  @type timeline_page :: %{groups: [Timeline.group()], next_cursor: binary | nil}

  @doc """
  Lista as fotos não-deletadas da Tekoa para a grade, **mais recém-enviadas
  primeiro** (`inserted_at DESC`), paginadas por cursor de keyset.

  ## Opções

    * `:limit` - itens por página (default: 50)
    * `:after_cursor` - cursor opaco devolvido em `next_cursor`
  """
  @callback list_photos(Scope.t(), keyword) :: {:ok, photo_page()}

  @doc """
  Linha do tempo: fotos ordenadas pela **data de captura** (EXIF quando houver,
  senão data de upload), mais recentes primeiro, agrupadas por dia e paginadas
  por cursor de keyset composto `(data_efetiva, id)`.

  ## Opções

    * `:limit` - fotos por página antes do agrupamento (default: 50)
    * `:after_cursor` - cursor opaco devolvido em `next_cursor`
  """
  @callback timeline(Scope.t(), keyword) :: {:ok, timeline_page()}
end
