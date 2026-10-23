defmodule Ypy.LexiconTest do
  use ExUnit.Case, async: true

  alias Ypy.Lexicon

  @file_record %{
    "type" => "object",
    "required" => ["name"],
    "properties" => %{
      "name" => %{"type" => "string", "maxLength" => 100},
      "folder" => %{"type" => "ref", "ref" => "#folderRef"}
    }
  }

  @file_lexicon %{
    "id" => "ypy.file.v0",
    "defs" => %{
      "main" => %{"type" => "record", "record" => @file_record},
      "folderRef" => %{"type" => "string"}
    }
  }

  # O jogo de fixtures da union: um lexicon com o campo de union e outro com
  # o def que a variante de outro lexicon nomeia.
  @post_lexicon %{
    "id" => "x.post.v0",
    "defs" => %{
      "main" => %{
        "type" => "record",
        "record" => %{
          "type" => "object",
          "properties" => %{
            "tag" => %{"type" => "union", "refs" => ["#textTag", "x.meta.v0#tagRef"]}
          }
        }
      },
      "textTag" => %{"type" => "string"}
    }
  }

  @meta_lexicon %{
    "id" => "x.meta.v0",
    "defs" => %{
      "main" => %{
        "type" => "record",
        "record" => %{"type" => "object", "properties" => %{"label" => %{"type" => "string"}}}
      },
      "tagRef" => %{"type" => "integer"}
    }
  }

  describe "load/1" do
    @tag :tmp_dir
    test "indexes directories in order, a later one replacing an earlier one", %{tmp_dir: tmp} do
      kernel = Path.join(tmp, "kernel")
      produto = Path.join(tmp, "produto")
      File.mkdir_p!(kernel)
      File.mkdir_p!(produto)

      write_lexicon(kernel, @file_lexicon)
      write_lexicon(kernel, @post_lexicon)

      substituto = put_in(@file_lexicon["defs"]["main"]["record"]["required"], ["name", "zona"])
      write_lexicon(produto, substituto)

      {index, problems} = Lexicon.load([kernel, produto])

      assert Map.keys(index) == ["x.post.v0", "ypy.file.v0"]
      assert index["ypy.file.v0"]["defs"]["main"]["record"]["required"] == ["name", "zona"]
      assert problems == []
    end

    @tag :tmp_dir
    test "a broken file becomes a problem, not an exception", %{tmp_dir: tmp} do
      File.write!(Path.join(tmp, "broken.json"), "{nao json")
      File.write!(Path.join(tmp, "noid.json"), ~s({"defs": {}}))
      write_lexicon(tmp, @file_lexicon)

      {index, problems} = Lexicon.load([tmp])

      assert Map.keys(index) == ["ypy.file.v0"]

      assert problems |> Enum.map(&elem(&1, 1)) |> Enum.sort() ==
               [:no_id, {:bad_json, {:invalid_byte, 1, 110}}]
    end
  end

  describe "record_schema/2" do
    test "follows local and cross-lexicon refs, and resolves union members" do
      index = index_of([@file_lexicon, @post_lexicon, @meta_lexicon])

      schema = Lexicon.record_schema("ypy.file.v0", index)

      assert schema["properties"]["folder"] == %{"type" => "string"}
      assert schema["properties"]["name"] == %{"type" => "string", "maxLength" => 100}

      union = Lexicon.record_schema("x.post.v0", index)["properties"]["tag"]

      assert union["defs"] == @post_lexicon["defs"]
      assert union["variants"]["#textTag"] == %{"type" => "string"}
      assert union["variants"]["x.meta.v0#tagRef"] == %{"type" => "integer"}
    end

    test "a ref naming a missing lexicon stays as it is" do
      solo =
        %{
          "id" => "solo.v0",
          "defs" => %{
            "main" => %{
              "type" => "record",
              "record" => %{
                "type" => "object",
                "properties" => %{"x" => %{"type" => "ref", "ref" => "falta.v0#x"}}
              }
            }
          }
        }

      schema = Lexicon.record_schema("solo.v0", index_of([solo]))

      assert schema["properties"]["x"] == %{"type" => "ref", "ref" => "falta.v0#x"}
    end

    test "two lexicons that reference each other terminate" do
      a = %{
        "id" => "a.v0",
        "defs" => %{
          "main" => %{"type" => "record", "record" => %{"type" => "ref", "ref" => "#b"}},
          "b" => %{"type" => "ref", "ref" => "#b"}
        }
      }

      schema = Lexicon.record_schema("a.v0", index_of([a]))

      assert schema == %{"type" => "ref", "ref" => "#b"}
    end

    test "answers nil for a collection with no lexicon and with no record def" do
      index = index_of([@file_lexicon])

      assert Lexicon.record_schema("falta.v0", index) == nil

      sem_record = %{"id" => "sem.v0", "defs" => %{"main" => %{"type" => "token"}}}

      assert Lexicon.record_schema("sem.v0", index_of([sem_record])) == nil
    end
  end

  defp write_lexicon(dir, lexicon) do
    nome = String.replace(lexicon["id"], ".", "-") <> ".json"
    File.write!(Path.join(dir, nome), JSON.encode!(lexicon))
  end

  defp index_of(lexicons) do
    Map.new(lexicons, fn lexicon -> {lexicon["id"], lexicon} end)
  end
end
