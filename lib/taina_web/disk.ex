defmodule TainaWeb.Disk do
  @moduledoc """
  Tamanho e folga do disco da comunidade, para a interface.

  O núcleo guarda o uso lógico dos arquivos (`Ybira.storage_stats/1`), não o
  tamanho do disco onde eles moram: sem cota (disco inteiro) a tela precisa
  desse número de fora para dizer "X de Y". É o mesmo `df` que a instalação
  já usa, restrito à interface: nenhum contexto depende dele.

      iex> TainaWeb.Disk.total_bytes()
      256_000_000_000
  """

  @doc """
  Tamanho total e espaço livre do disco da comunidade, ou `nil` quando o
  sistema não responde (a interface então cala o número em vez de inventar).
  """
  def stats do
    storage_root = Application.fetch_env!(:taina, :storage_root)

    with {out, 0} <- System.cmd("df", ["-k", storage_root], stderr_to_stdout: true),
         [_header, line | _rest] <- String.split(out, "\n"),
         [_fs, blocks, _used, available | _] <- String.split(line, ~r/\s+/, trim: true),
         {blocks, ""} <- Integer.parse(blocks),
         {available, ""} <- Integer.parse(available) do
      {:ok, %{total_bytes: blocks * 1024, free_bytes: available * 1024}}
    else
      _other -> {:error, :unavailable}
    end
  rescue
    _error in ErlangError -> {:error, :unavailable}
  end

  @doc "Tamanho total do disco em bytes, ou `nil` quando não dá para ler."
  def total_bytes do
    case stats() do
      {:ok, %{total_bytes: total}} -> total
      {:error, _reason} -> nil
    end
  end
end
