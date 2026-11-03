defmodule Taina.ReleaseTest do
  use ExUnit.Case, async: true

  import Bitwise

  test "creates a secret with mode 0600 and parent directories" do
    path = Path.join(tmp_dir(), "nested/secret_key_base")
    assert :ok = Taina.Release.ensure_secret!(path)
    assert (File.stat!(path).mode &&& 0o777) == 0o600
    assert byte_size(File.read!(path)) > 0
  end

  test "reuses existing secret contents and tightens its mode" do
    path = Path.join(tmp_dir(), "secret_key_base")
    File.write!(path, "existing-secret")
    File.chmod!(path, 0o644)

    assert :ok = Taina.Release.ensure_secret!(path)
    assert File.read!(path) == "existing-secret"
    assert (File.stat!(path).mode &&& 0o777) == 0o600
  end

  test "password reader falls back to stdin when no echo input reaches eof" do
    ExUnit.CaptureIO.capture_io("new-password\nnew-password\n", fn ->
      assert {:ok, "new-password"} = Taina.CLI.read_password()
    end)
  end

  defp tmp_dir do
    path = Path.join(System.tmp_dir!(), "taina_release_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end
end
