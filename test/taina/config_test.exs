defmodule Taina.ConfigTest do
  use ExUnit.Case, async: true

  alias Taina.Config

  @valid """
  url_scheme = https
  hostname = example.org
  url_port = 443
  bind_ip = 0.0.0.0
  port = 4000
  data_dir = /data
  storage_dir = /storage
  backup_dir = /backups
  backup_enabled = true
  update_check = false
  """

  test "parses typed settings and derives defaults" do
    assert {:ok, entries} = Config.parse(@valid)
    assert entries["port"] == {"4000", 5}
    assert {:ok, settings} = Config.effective(write_config(@valid))
    assert settings.port == 4000
    assert settings.bind_ip == {0, 0, 0, 0}
    assert settings.url_scheme == :https
  end

  test "rejects unknown and duplicate keys with line numbers" do
    assert {:error, {:unknown_key, "wat", 1}} = Config.parse("wat = nope")
    assert {:error, {:duplicate_key, "port", 2}} = Config.parse("port = 4000\nport = 4001")
  end

  test "rejects invalid typed values" do
    path = write_config(String.replace(@valid, "port = 4000", "port = nope"))
    assert {:error, {:invalid, ^path, {:invalid_value, "port", 5}}} = Config.effective(path)
    assert Config.describe({:invalid_value, "port", 5}) =~ "port on line 5"
  end

  test "loads the release settings under the taina application" do
    path = write_config(@valid)
    System.put_env("TAINA_CONFIG_TEST", path)
    on_exit(fn -> System.delete_env("TAINA_CONFIG_TEST") end)

    config = Config.load([], {:system, "TAINA_CONFIG_TEST"})

    assert config[:taina][:config].port == 4000
    assert config[:taina][Taina.Repo][:database] == "/data/taina.db"
    assert config[:taina][:storage_root] == "/storage"
  end

  test "template contains no secret value" do
    refute Config.template() =~ "SECRET_KEY_BASE"
    assert Config.template() =~ "secret_key_base_file"
  end

  defp write_config(text) do
    path = Path.join(System.tmp_dir!(), "taina-config-#{System.unique_integer([:positive])}.conf")
    File.write!(path, text)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
