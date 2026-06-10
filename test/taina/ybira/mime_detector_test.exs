defmodule Taina.Ybira.MimeDetectorTest do
  use ExUnit.Case, async: true

  alias Taina.Ybira.MimeDetector

  defp detect(bytes) do
    path = Path.join(System.tmp_dir!(), "mime_#{System.unique_integer([:positive])}")
    File.write!(path, bytes)
    on_exit_rm(path)
    MimeDetector.detect(path)
  end

  defp on_exit_rm(path), do: ExUnit.Callbacks.on_exit(fn -> File.rm(path) end)

  test "recognizes common formats by magic bytes" do
    assert detect(<<0xFF, 0xD8, 0xFF, 0xE0, 0, 0>>) == "image/jpeg"
    assert detect(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>) == "image/png"
    assert detect("GIF89a....") == "image/gif"
    assert detect(<<"RIFF", 0, 0, 0, 0, "WEBP">>) == "image/webp"
    assert detect("%PDF-1.4") == "application/pdf"
    assert detect(<<"PK", 0x03, 0x04, 0, 0>>) == "application/zip"
    assert detect("OggS....") == "audio/ogg"
    assert detect("fLaC....") == "audio/flac"
  end

  test "reads the ftyp brand for ISO-BMFF containers" do
    assert detect(<<0, 0, 0, 0x18, "ftyp", "mp42", 0, 0>>) == "video/mp4"
    assert detect(<<0, 0, 0, 0x18, "ftyp", "qt  ", 0, 0>>) == "video/quicktime"
    assert detect(<<0, 0, 0, 0x18, "ftyp", "heic", 0, 0>>) == "image/heic"
  end

  test "detects executables (which the upload allowlist rejects)" do
    assert detect(<<0x4D, 0x5A, 0x90, 0x00>>) == "application/x-msdownload"
    assert detect(<<0x7F, "ELF", 0, 0>>) == "application/x-executable"
  end

  test "falls back to text/plain for readable content and octet-stream otherwise" do
    assert detect("apenas um texto qualquer, com acento á") == "text/plain"
    assert detect(<<0, 1, 2, 3, 0, 5>>) == "application/octet-stream"
    assert detect("") == "application/octet-stream"
  end

  test "returns octet-stream for a missing file" do
    assert MimeDetector.detect("/tmp/nao_existe_#{System.unique_integer([:positive])}") ==
             "application/octet-stream"
  end
end
