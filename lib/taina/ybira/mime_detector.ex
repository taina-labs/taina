defmodule Taina.Ybira.MimeDetector do
  @moduledoc """
  Detecta o tipo MIME de um arquivo pelos *magic bytes* — os primeiros bytes do
  conteúdo — em vez de confiar na extensão do nome.

  A extensão mente: qualquer um renomeia `malware.exe` para `foto.jpg`. Ler o
  cabeçalho real fecha essa brecha e alimenta a allowlist de `Taina.Ybira`, que
  rejeita executáveis e formatos fora da lista.

  Casamento puro em Elixir sobre os 32 primeiros bytes, sem NIF nem dependência
  externa. Quando nenhum padrão binário casa, cai para `text/plain` se o trecho
  for texto legível, ou `application/octet-stream` caso contrário.
  """

  @header_bytes 32

  @doc """
  Lê os primeiros #{@header_bytes} bytes de `path` e devolve o MIME detectado.

  Em qualquer falha de leitura devolve `"application/octet-stream"`.
  """
  @spec detect(Path.t()) :: String.t()
  def detect(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, @header_bytes)) do
      {:ok, header} when is_binary(header) -> match_magic(header)
      _ -> "application/octet-stream"
    end
  end

  # --- Imagens ---
  defp match_magic(<<0xFF, 0xD8, 0xFF, _::binary>>), do: "image/jpeg"
  defp match_magic(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>), do: "image/png"
  defp match_magic(<<"GIF87a", _::binary>>), do: "image/gif"
  defp match_magic(<<"GIF89a", _::binary>>), do: "image/gif"
  defp match_magic(<<"RIFF", _::32, "WEBP", _::binary>>), do: "image/webp"

  # --- Contêineres ISO-BMFF (ftyp): mp4 / mov / heic ---
  defp match_magic(<<_::32, "ftyp", brand::binary-size(4), _::binary>>), do: ftyp_mime(brand)

  # --- Vídeo / Áudio em outros contêineres ---
  defp match_magic(<<"RIFF", _::32, "AVI ", _::binary>>), do: "video/avi"
  defp match_magic(<<"RIFF", _::32, "WAVE", _::binary>>), do: "audio/wav"
  defp match_magic(<<0x1A, 0x45, 0xDF, 0xA3, _::binary>>), do: "video/webm"
  defp match_magic(<<"OggS", _::binary>>), do: "audio/ogg"
  defp match_magic(<<"fLaC", _::binary>>), do: "audio/flac"
  defp match_magic(<<"ID3", _::binary>>), do: "audio/mpeg"
  defp match_magic(<<0xFF, 0xFB, _::binary>>), do: "audio/mpeg"
  defp match_magic(<<0xFF, 0xF3, _::binary>>), do: "audio/mpeg"
  defp match_magic(<<0xFF, 0xF2, _::binary>>), do: "audio/mpeg"

  # --- Documentos / arquivos ---
  defp match_magic(<<"%PDF", _::binary>>), do: "application/pdf"
  defp match_magic(<<"PK", 0x03, 0x04, _::binary>>), do: "application/zip"

  # --- Executáveis (NÃO permitidos pela allowlist; detectar é o ponto) ---
  defp match_magic(<<0x4D, 0x5A, _::binary>>), do: "application/x-msdownload"
  defp match_magic(<<0x7F, "ELF", _::binary>>), do: "application/x-executable"
  defp match_magic(<<0xFE, 0xED, 0xFA, 0xCE, _::binary>>), do: "application/x-mach-binary"
  defp match_magic(<<0xFE, 0xED, 0xFA, 0xCF, _::binary>>), do: "application/x-mach-binary"
  defp match_magic(<<0xCF, 0xFA, 0xED, 0xFE, _::binary>>), do: "application/x-mach-binary"
  defp match_magic(<<0xCA, 0xFE, 0xBA, 0xBE, _::binary>>), do: "application/x-mach-binary"

  # --- Fallback: texto legível vs binário desconhecido ---
  defp match_magic(header) do
    if printable_text?(header), do: "text/plain", else: "application/octet-stream"
  end

  defp ftyp_mime("qt  "), do: "video/quicktime"
  defp ftyp_mime(brand) when brand in ~w(heic heix hevc heim heis mif1), do: "image/heic"
  defp ftyp_mime(_brand), do: "video/mp4"

  # Heurística: UTF-8 válido e sem byte NUL ⇒ tratamos como texto. O trecho lido
  # pode cortar um caractere multibyte no fim; nesse caso `String.valid?` falha e
  # o arquivo vira octet-stream — que a allowlist ainda aceita.
  defp printable_text?(<<>>), do: false

  defp printable_text?(header) do
    String.valid?(header) and not String.contains?(header, <<0>>)
  end
end
