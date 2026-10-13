defmodule Taina.CLITest do
  use ExUnit.Case, async: false

  alias Taina.CLI

  # Módulo exclusive (async: false) porque mexe em Application env, que é
  # global no VM.
  setup do
    original = Application.fetch_env!(:taina, :backup)
    on_exit(fn -> Application.put_env(:taina, :backup, original) end)
    :ok
  end

  describe "parse/1" do
    test "verbos conhecidos viram comando" do
      assert {:ok, %CLI{verb: :backup, opts: []}} = CLI.parse(["backup"])
      assert {:ok, %CLI{verb: :backup, opts: [dir: "/mnt/usb"]}} = CLI.parse(["backup", "--out", "/mnt/usb"])

      assert {:ok, %CLI{verb: :restore, opts: [archive: "b.tar.gz"]}} =
               CLI.parse(["restore", "b.tar.gz"])

      assert {:ok, %CLI{verb: :doctor}} = CLI.parse(["doctor"])
      assert {:ok, %CLI{verb: :version}} = CLI.parse(["version"])
    end

    test "argv vazio, verbo desconhecido ou flags incompletos são erro de uso" do
      assert {:error, :usage} = CLI.parse([])
      assert {:error, :usage} = CLI.parse(["qualquer-coisa"])
      assert {:error, :usage} = CLI.parse(["backup", "--out"])
      assert {:error, :usage} = CLI.parse(["backup", "extra"])
      assert {:error, :usage} = CLI.parse(["restore"])
      assert {:error, :usage} = CLI.parse(["version", "extra"])
      assert {:error, :usage} = CLI.parse(["--out", "x", "backup"])
    end
  end

  describe "run/1 usage" do
    test "sem verbo: uso no stderr, código 2" do
      output = capture_stderr(fn -> assert 2 = CLI.run([]) end)

      assert output =~ "uso: taina <verbo> [opções]"
      assert output =~ "backup"
      assert output =~ "restore"
      assert output =~ "doctor"
      assert output =~ "version"
    end

    test "verbo desconhecido: uso no stderr, código 2" do
      output = capture_stderr(fn -> assert 2 = CLI.run(["faca-um-backup"]) end)
      assert output =~ "uso: taina <verbo> [opções]"
    end
  end

  describe "run/1 version" do
    test "imprime a versão do app e devolve 0" do
      output = ExUnit.CaptureIO.capture_io(fn -> assert 0 = CLI.run(["version"]) end)
      assert output =~ to_string(Application.spec(:taina, :vsn))
    end
  end

  describe "run/1 backup" do
    test "sem --out e sem destino na config: código 3 (ambiente)" do
      Application.put_env(:taina, :backup, enabled: false, dir: nil)

      output = capture_stderr(fn -> assert 3 = CLI.run(["backup"]) end)
      assert output =~ "backup sem destino"
    end

    test "com --out: imprime o caminho do arquivo criado e devolve 0" do
      dir = tmp_dir()

      output = ExUnit.CaptureIO.capture_io(fn -> assert 0 = CLI.run(["backup", "--out", dir]) end)

      assert [path] = String.split(output, "\n", trim: true)
      assert String.starts_with?(path, dir)
      assert File.exists?(path)
    end
  end

  describe "run/1 restore" do
    test "arquivo inexistente: falha de domínio no stderr, código 1" do
      archive = Path.join(tmp_dir(), "nao-existe.tar.gz")

      output = capture_stderr(fn -> assert 1 = CLI.run(["restore", archive]) end)
      assert output =~ "restore falhou"
    end
  end

  describe "run/1 doctor" do
    setup do
      # O storage de teste só existe quando algo o cria; o doctor lê o dir.
      File.mkdir_p!(Application.fetch_env!(:taina, :storage_root))
      :ok
    end

    test "imprime o diagnóstico completo e devolve 0 com o ambiente sadio" do
      output = ExUnit.CaptureIO.capture_io(fn -> assert 0 = CLI.run(["doctor"]) end)

      assert output =~ "versão: #{to_string(Application.spec(:taina, :vsn))}"
      assert output =~ "banco de dados: #{Application.fetch_env!(:taina, Taina.Repo)[:database]}"
      assert output =~ "armazenamento: #{Application.fetch_env!(:taina, :storage_root)}"
      assert output =~ ~r/migrações: \d+ aplicadas, 0 pendentes/
      assert output =~ "backup:"
      assert output =~ "último backup:"
    end

    test "banco configurado mas ausente: código 3 e a linha diz não acessível" do
      config = Application.fetch_env!(:taina, Taina.Repo)
      original = {config, Application.get_env(:taina, :storage_root)}

      Application.put_env(:taina, Taina.Repo, Keyword.put(config, :database, tmp_file()))
      Application.put_env(:taina, :storage_root, Path.join(tmp_dir(), "nunca-criado"))

      output = ExUnit.CaptureIO.capture_io(fn -> assert 3 = CLI.run(["doctor"]) end)
      assert output =~ "não acessível"
      assert output =~ "diretório não existe"

      on_exit(fn ->
        {config, storage} = original
        Application.put_env(:taina, Taina.Repo, config)
        Application.put_env(:taina, :storage_root, storage)
      end)
    end
  end

  defp capture_stderr(fun), do: ExUnit.CaptureIO.capture_io(:stderr, fun)

  defp tmp_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "taina_cli_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp tmp_file, do: Path.join(tmp_dir(), "nunca-criado.db")
end
