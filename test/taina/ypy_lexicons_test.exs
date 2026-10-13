defmodule Taina.YpyLexiconsTest do
  use ExUnit.Case, async: true

  # O boot carrega o registro de lexicons (kernel primeiro, produto depois,
  # RFC_006 secao 6); as colecoes do kernel precisam estar resolvidas antes
  # de qualquer escrita de record.
  test "o registro conhece as colecoes do kernel" do
    assert Ypy.Lexicon.Registry.knows?("ypy.file.v0")
    assert Ypy.Lexicon.Registry.knows?("ypy.folder.v0")
  end

  test "colecao sem lexicon nao e conhecida" do
    refute Ypy.Lexicon.Registry.knows?("taina.inexistente.v0")
  end
end
