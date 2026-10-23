defmodule Ypy.Wire.File do
  @moduledoc """
  O arquivo e a pasta no fio (RFC_005 secao 9): os metadados que a API
  devolve de um lado, os enderecos do mundo CBOR do outro. O `rkey` e o id
  publico (TID, RFC_006 secao 12), o `cid` endereco o envelope do record, o
  `blob_cid` os bytes no `Ypy.BlobStore` e o `sha256` e o hash deles, para o
  cliente de backup pular o que ja subiu.

  A pasta pai entra como o rkey dela, quando o belong_to (`folder` do
  arquivo, `parent` da pasta) veio preload; sem preload, null. O dono sai
  pelo `public_id` dele, mesmo jogo: com preload, o id; sem preload, null.
  """

  alias Ypy.Maraca.Ava
  alias Ypy.Wire
  alias Ypy.Ybira.File
  alias Ypy.Ybira.Folder

  @doc "O mapa JSON do arquivo ou da pasta."
  @spec json(File.t()) :: map()
  def json(%File{} = file) do
    %{
      "rkey" => file.rkey,
      "cid" => file.cid,
      "blob_cid" => file.blob_cid,
      "sha256" => file.hash,
      "name" => file.nome,
      "mime" => file.mime,
      "size" => file.tamanho,
      "zona" => zona(file.zona),
      "folder" => folder_rkey(file.folder),
      "dono" => dono_public_id(file.dono),
      "deleted_at" => Wire.at(file.apagado_em),
      "created_at" => Wire.at(file.inserted_at),
      "updated_at" => Wire.at(file.updated_at)
    }
  end

  def json(%Folder{} = folder) do
    %{
      "rkey" => folder.rkey,
      "cid" => folder.cid,
      "name" => folder.nome,
      "zona" => zona(folder.zona),
      "folder" => folder_rkey(folder.parent),
      "dono" => dono_public_id(folder.dono),
      "deleted_at" => Wire.at(folder.apagado_em),
      "created_at" => Wire.at(folder.inserted_at),
      "updated_at" => Wire.at(folder.updated_at)
    }
  end

  defp zona(:casa), do: "casa"
  defp zona(:praca), do: "praca"

  defp folder_rkey(%Folder{rkey: rkey}), do: rkey
  defp folder_rkey(_), do: nil

  defp dono_public_id(%Ava{public_id: public_id}), do: public_id
  defp dono_public_id(_), do: nil
end
