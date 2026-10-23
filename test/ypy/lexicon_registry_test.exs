defmodule Ypy.Lexicon.RegistryTest do
  use ExUnit.Case, async: false

  alias Ypy.Lexicon.Registry

  @file_lexicon %{
    "id" => "ypy.file.v0",
    "defs" => %{
      "main" => %{
        "type" => "record",
        "record" => %{
          "type" => "object",
          "required" => ["name"],
          "properties" => %{"name" => %{"type" => "string"}}
        }
      }
    }
  }

  setup do
    :persistent_term.erase(Registry)

    # Os fixtures moram no tmp do sistema e vazariam de teste para teste e de
    # rodada para rodada (o unique_integer volta ao mesmo valor em cada no
    # novo): limpar o proprio diretorio em cada saida.
    base = Path.join(System.tmp_dir!(), "ypy-registry-#{System.unique_integer([:positive])}")

    on_exit(fn ->
      Ypy.PersistenceCase.load_lexicons()
      File.rm_rf!(base)
    end)

    {:ok, base: base}
  end

  test "load/1 installs the index and the reads answer from it", %{base: kernel} do
    produto = Path.join(kernel, "produto")

    File.mkdir_p!(kernel)
    write(kernel, @file_lexicon)

    File.mkdir_p!(produto)

    assert Registry.record("ypy.file.v0") == nil
    assert Registry.knows?("ypy.file.v0") == false
    assert Registry.all() == %{}

    {index, problems} = Registry.load([kernel, produto])

    assert problems == []
    assert index["ypy.file.v0"] == @file_lexicon

    assert Registry.all() == %{"ypy.file.v0" => @file_lexicon}
    assert Registry.get("ypy.file.v0") == @file_lexicon
    assert Registry.get("falta.v0") == nil
    assert Registry.record("ypy.file.v0")["properties"]["name"] == %{"type" => "string"}
    assert Registry.record("falta.v0") == nil
    assert Registry.knows?("ypy.file.v0") == true
    assert Registry.knows?("falta.v0") == false
  end

  test "a broken lexicon in the product dir loads the rest and reports", %{base: dir} do
    File.mkdir_p!(dir)

    write(dir, @file_lexicon)
    File.write!(Path.join(dir, "quebrado.json"), "{errado")

    {_index, problems} = Registry.load([dir])

    assert [{_path, {:bad_json, _}}] = problems
    assert Registry.knows?("ypy.file.v0") == true
  end

  defp write(dir, lexicon) do
    nome = String.replace(lexicon["id"], ".", "-") <> ".json"
    File.write!(Path.join(dir, nome), JSON.encode!(lexicon))
  end
end
