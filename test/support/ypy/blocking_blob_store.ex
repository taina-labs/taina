defmodule Ypy.BlobStore.Blocking do
  @moduledoc false
  alias Ypy.BlobStore.Disk

  defstruct [:disk, :owner]

  def new(disk, owner), do: %__MODULE__{disk: disk, owner: owner}

  def put_file(%__MODULE__{disk: disk, owner: owner}, source) do
    result = Disk.put_file(disk, source)
    caller = self()
    send(owner, {:blob_written, caller, result})

    receive do
      :continue_blob -> result
    end
  end

  def delete(%__MODULE__{disk: disk}, cid), do: Disk.delete(disk, cid)
end
