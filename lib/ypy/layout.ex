defmodule Ypy.Layout do
  @moduledoc """
  O layout de estado de uma Tekoa: um diretorio de dados se resolve em
  arquivo de banco, blobs/ e keys/.

      /var/lib/taina
        db.sqlite
        blobs/
        keys/

  E a unidade de portabilidade da Tekoa (RFC_006, secao 6): o que backup e
  exportacao precisam cobrir sao exatamente esses tres caminhos, mais a
  cadeia, que vive no banco. Matematica de caminhos, pura: abrir os arquivos
  e trabalho do produto (`Ypy.BlobStore.Disk`, `Ypy.KeyStore.Files`).
  """

  @enforce_keys [:dir, :db, :blobs, :keys]
  defstruct [:dir, :db, :blobs, :keys]

  @type t :: %__MODULE__{dir: Path.t(), db: Path.t(), blobs: Path.t(), keys: Path.t()}

  @doc "Resolve o layout a partir do diretorio de dados."
  def from_dir(dir) when is_binary(dir) do
    %__MODULE__{
      dir: dir,
      db: Path.join(dir, "db.sqlite"),
      blobs: Path.join(dir, "blobs"),
      keys: Path.join(dir, "keys")
    }
  end
end
