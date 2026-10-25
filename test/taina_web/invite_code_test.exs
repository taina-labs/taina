defmodule TainaWeb.InviteCodeTest do
  use ExUnit.Case, async: true

  alias TainaWeb.InviteCode

  describe "parse/1 (sem host da requisição)" do
    test "código cru vale" do
      assert {:ok, "abc123"} = InviteCode.parse("abc123")
      assert {:ok, "AbC_-9"} = InviteCode.parse("  AbC_-9  ")
    end

    test "link completo vale, qualquer host, com ou sem esquema" do
      assert {:ok, "abc123"} = InviteCode.parse("https://taina.local/convite/abc123")
      assert {:ok, "abc123"} = InviteCode.parse("http://localhost:4000/convite/abc123")
      assert {:ok, "abc123"} = InviteCode.parse("taina.local/convite/abc123")
      assert {:ok, "abc123"} = InviteCode.parse("https://outra-nuvem.org/convite/abc123")
      assert {:ok, "abc123"} = InviteCode.parse("https://taina.local/convite/abc123/")
    end

    test "link de outro host é aceito aqui: quem confere o host é a tela (parse/2)" do
      assert {:ok, "abc123"} = InviteCode.parse("https://outra-nuvem.org/convite/abc123")
    end

    test "lixo não vale" do
      assert {:error, :invalid} = InviteCode.parse("")
      assert {:error, :invalid} = InviteCode.parse(nil)
      assert {:error, :invalid} = InviteCode.parse("oi tudo bem")
      assert {:error, :invalid} = InviteCode.parse("abc123!!!")
      assert {:error, :invalid} = InviteCode.parse("https://taina.local/documentos")
      assert {:error, :invalid} = InviteCode.parse("https://taina.local/convite/abc123?x=1")
    end
  end

  describe "parse/2 (com o host da requisição)" do
    test "link desta comunidade vale" do
      assert {:ok, "abc123"} = InviteCode.parse("https://taina.local/convite/abc123", "taina.local")
      assert {:ok, "abc123"} = InviteCode.parse("https://TAINA.local:4000/convite/abc123", "taina.local")
      assert {:ok, "abc123"} = InviteCode.parse("http://www.example.com/convite/abc123", "www.example.com")
    end

    test "link de outra comunidade não vale: a web não troca de instância" do
      assert {:error, :other_community} =
               InviteCode.parse("https://outra-nuvem.org/convite/abc123", "taina.local")
    end

    test "só o código não tem comunidade a conferir" do
      assert {:ok, "abc123"} = InviteCode.parse("abc123", "taina.local")
    end
  end
end
