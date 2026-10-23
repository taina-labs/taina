defmodule Ypy.BlobStore do
  @moduledoc """
  Guarda e devolve bytes enderecados por conteudo.

  A impl escolhe o produto: o box guarda em disco (`Ypy.BlobStore.Disk`), o
  hospedado pode apontar para um volume. Os bytes nunca mudam de conteudo: o
  CID devolvido pelo `put/2` e o endereco pelo qual o `fetch/2`, o `stat/2`
  e o `open/2` os alcancam.
  """

  alias Ypy.Cid

  @typedoc "A impl do produto."
  @type t :: struct()

  @typedoc "Caminho de arquivo (quando a impl serve o blob direto do disco)."
  @type path :: String.t()

  @doc "Escreve os bytes e devolve o CID deles."
  @callback put(t(), binary()) :: {:ok, Cid.t()} | {:error, term()}

  @doc "Le os bytes de um CID."
  @callback fetch(t(), Cid.t()) :: {:ok, binary()} | {:error, :not_found}

  @doc "O tamanho dos bytes de um CID."
  @callback stat(t(), Cid.t()) :: {:ok, %{size: pos_integer()}} | {:error, :not_found}

  @doc """
  O caminho local do blob, quando a impl serve o arquivo direto (download e
  streaming sem carregar na memoria). Uma impl sem caminho responde
  {:error, :unsupported}.
  """
  @callback open(t(), Cid.t()) :: {:ok, path()} | {:error, :not_found | :unsupported}

  @doc "Apaga o blob de um CID. Blob ausente responde {:error, :not_found}."
  @callback delete(t(), Cid.t()) :: :ok | {:error, :not_found}

  @doc """
  Escreve os bytes do arquivo em `path` e devolve o CID deles, sem ler o
  conteudo na memoria. Opcional: quem chama recorre ao `put/2` quando a impl
  nao exporta.
  """
  @callback put_file(t(), path()) :: {:ok, Cid.t()} | {:error, term()}

  @optional_callbacks put_file: 2
end
