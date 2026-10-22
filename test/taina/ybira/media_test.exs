defmodule Taina.Ybira.MediaTest do
  use ExUnit.Case, async: true

  alias Taina.Ybira.Media

  describe "extract_taken_at/1" do
    test "usa a data original do EXIF, já decodificada como NaiveDateTime" do
      exif = %{
        datetime_original: ~N[2023-07-15 14:30:00],
        modify_date: ~N[2024-01-01 00:00:00]
      }

      assert Media.extract_taken_at(exif) == ~N[2023-07-15 14:30:00]
    end

    test "não estoura com structs aninhados (NaiveDateTime, GPS, thumbnail)" do
      # Regressão: um NaiveDateTime é um struct, logo também um mapa. Varrer o
      # EXIF com Enum.reduce/3 sobre ele estourava `Protocol.UndefinedError`
      # (Enumerable não implementado) e derrubava a rendition inteira.
      exif = %{
        make: "Canon",
        gps: %Image.Exif.Gps{},
        thumbnail: %Image.Exif.Thumbnail{},
        exif: %{datetime_original: ~N[2023-07-15 14:30:00]}
      }

      assert Media.extract_taken_at(exif) == ~N[2023-07-15 14:30:00]
    end

    test "ainda lê a string crua do EXIF como rede de segurança" do
      assert Media.extract_taken_at(%{datetime_original: "2023:07:15 14:30:00"}) ==
               ~N[2023-07-15 14:30:00]
    end

    test "sem data no EXIF devolve nil" do
      assert Media.extract_taken_at(%{make: "Canon"}) == nil
      assert Media.extract_taken_at(nil) == nil
    end
  end

  # Puro: classifica o termo de erro sem tocar em imagem nem disco.
  describe "unsupported_format?/1" do
    test "reconhece as frases de loader ausente da libvips" do
      # frase atual da libvips para arquivo que nenhum loader reconhece
      assert Media.unsupported_format?(error("open /x/a: Failed to find load"))
      # frase de builds antigos
      assert Media.unsupported_format?(%Image.Error{message: "is not a known file format"})
      # variantes genéricas
      assert Media.unsupported_format?(%Image.Error{message: "HEIF decoding not supported in this build"})
      assert Media.unsupported_format?("unsupported format combination")
    end

    test "não confunde outros erros com formato sem suporte" do
      refute Media.unsupported_format?(error("open /x/a: truncated image"))
      refute Media.unsupported_format?(:enoent)
      refute Media.unsupported_format?(nil)
      refute Media.unsupported_format?({:error, :enoent})
    end
  end

  defp error(message) do
    struct(Image.Error, message: message, reason: message, operation: :open, path: "/x/a")
  end
end
