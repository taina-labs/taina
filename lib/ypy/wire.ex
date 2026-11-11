defmodule Ypy.Wire do
  @moduledoc """
  As convencoes do fio JSON (RFC_005 secao 6 e 7): a forma que os dados do
  kernel tomam na API do box, a ponte entre o mundo CBOR dos records e o
  mundo HTTP JSON dos clientes.

  As convencoes, sem excecao:

  - chaves de string e valores diretos de JSON, nada de struct ou binario cru;
  - data e hora vira ISO-8601 UTC por `at/1`, e ausente vira null;
  - os valores de enum vao como o nome do atomo em string (`"casa"`,
    `"zelador"`), a mesma palavra do banco, do contexto e da UI (RFC_006 D9);
  - o id publico de arquivo e pasta e o `rkey` (TID) e o de pessoa o
    `public_id`;
  - listas paginam no envelope de `page/2` e o conteudo de pasta no de
    `folder_page/3`, com as pastas completas e so os arquivos paginando;
  - todo erro segue o vocabulario de `Ypy.Wire.Errors`.

  Os shapes por recurso sao `Ypy.Wire.Ava`, `Ypy.Wire.File` (arquivos e
  pastas) e `Ypy.Wire.Mural`. Os components OpenAPI do fio moram no contrato
  do box, `priv/static/openapi.yaml`.
  """

  @doc false
  @type datetime :: DateTime.t()
  @type params :: map()
  @type text :: String.t()

  @spec at(nil | datetime()) :: nil | text()
  def at(nil), do: nil
  def at(%DateTime{} = quando), do: DateTime.to_iso8601(quando)

  @doc """
  O envelope do conteudo de pasta (RFC_005 secao 7): `{"folders": [...],
  "items": [...], "next_cursor": ...}`. As pastas vem completas, so os
  arquivos paginam.
  """
  @spec folder_page([params()], [params()], nil | text()) :: params()
  def folder_page(folders, items, next_cursor) do
    %{"folders" => folders, "items" => items, "next_cursor" => next_cursor}
  end

  @doc """
  O envelope uniforme de paginacao: `{"items": [...], "next_cursor": ...}`.

  Os itens chegam renderizados pelos shapes do `Ypy.Wire`; o cursor e sempre
  string ou null (RFC_005 secao 7).
  """
  @spec page([params()], nil | text()) :: params()
  def page(items, next_cursor), do: %{"items" => items, "next_cursor" => next_cursor}
end
