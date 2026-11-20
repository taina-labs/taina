defmodule Taina.Disk do
  @moduledoc """
  Physical disk capacity for the community storage.

  This is an infrastructure probe. Community file accounting remains in Ybira;
  callers use these values only as a best-effort capacity signal because the
  filesystem can change immediately after the probe.
  """

  @doc "Returns total and free bytes, or an error when the system cannot answer."
  @spec stats() :: {:ok, %{total_bytes: non_neg_integer(), free_bytes: non_neg_integer()}} | {:error, :unavailable}
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

  @doc "Returns total disk bytes, or nil when unavailable."
  @spec total_bytes() :: non_neg_integer() | nil
  def total_bytes do
    case stats() do
      {:ok, %{total_bytes: total}} -> total
      {:error, _reason} -> nil
    end
  end
end
