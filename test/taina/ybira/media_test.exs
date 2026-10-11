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
end
