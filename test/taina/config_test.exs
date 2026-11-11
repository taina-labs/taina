defmodule Taina.ConfigTest do
  # The tests read and write process-wide environment variables and application config.
  use ExUnit.Case, async: false

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
    assert settings.max_blob_size == 2 * 1024 * 1024 * 1024
    assert settings.max_concurrent_uploads == 10
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

  test "parses configured upload limits" do
    text = String.replace(@valid, "port = 4000", "port = 4000\nmax_blob_size = 104857600\nmax_concurrent_uploads = 3")

    assert {:ok, settings} = Config.effective(write_config(text))
    assert settings.max_blob_size == 104_857_600
    assert settings.max_concurrent_uploads == 3
  end

  test "rejects non-positive upload limits" do
    path = write_config(String.replace(@valid, "port = 4000", "port = 4000\nmax_blob_size = 0"))

    assert {:error, {:invalid, ^path, {:invalid_value, "max_blob_size", 6}}} = Config.effective(path)
  end

  test "loads the release settings under the taina application" do
    path = write_config(@valid)
    System.put_env("TAINA_CONFIG_TEST", path)
    on_exit(fn -> System.delete_env("TAINA_CONFIG_TEST") end)

    config = Config.load([], {:system, "TAINA_CONFIG_TEST"})
    taina = Keyword.fetch!(config, :taina)
    settings = Keyword.fetch!(taina, :config)
    upload = Keyword.fetch!(taina, :upload)
    repo = Keyword.fetch!(taina, Taina.Repo)
    endpoint = Keyword.fetch!(taina, TainaWeb.Endpoint)

    assert settings.port == 4000
    assert settings.max_blob_size == 2 * 1024 * 1024 * 1024
    assert Keyword.fetch!(upload, :max_concurrent_uploads) == 10
    assert Keyword.fetch!(repo, :database) == "/data/taina.db"
    assert Keyword.fetch!(taina, :storage_root) == "/storage"
    assert Keyword.fetch!(endpoint, :check_origin) == ["https://example.org"]
  end

  test "endpoint origin includes a non-default public port" do
    path = write_config(String.replace(@valid, "url_port = 443", "url_port = 8443"))
    previous = System.get_env("TAINA_CONFIG_TEST")
    System.put_env("TAINA_CONFIG_TEST", path)

    on_exit(fn ->
      if previous,
        do: System.put_env("TAINA_CONFIG_TEST", previous),
        else: System.delete_env("TAINA_CONFIG_TEST")
    end)

    config = Config.load([], {:system, "TAINA_CONFIG_TEST"})

    endpoint =
      config
      |> Keyword.fetch!(:taina)
      |> Keyword.fetch!(TainaWeb.Endpoint)

    assert Keyword.fetch!(endpoint, :check_origin) == ["https://example.org:8443"]
  end

  test "template contains no secret value" do
    refute Config.template() =~ "SECRET_KEY_BASE"
    assert Config.template() =~ "secret_key_base_file"
  end

  defp write_config(text) do
    path = Path.join(System.tmp_dir!(), "taina-config-#{System.unique_integer([:positive])}.conf")
    # This path is generated under the OS temp directory from a fixed prefix and unique integer.
    # credo:disable-for-next-line OeditusCredo.Check.Security.PathTraversal
    File.write!(path, text)
    # credo:disable-for-next-line OeditusCredo.Check.Security.PathTraversal
    on_exit(fn -> File.rm(path) end)
    path
  end
end
