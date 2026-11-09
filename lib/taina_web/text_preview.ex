defmodule TainaWeb.TextPreview do
  @moduledoc false

  @doc """
  Converts a byte prefix to valid UTF-8 for LiveView state.

  An incomplete final codepoint is omitted. Invalid bytes elsewhere make the
  preview unavailable.
  """
  def decode(bytes) when is_binary(bytes) do
    case :unicode.characters_to_binary(bytes, :utf8, :utf8) do
      text when is_binary(text) -> text
      {:incomplete, text, _rest} when is_binary(text) -> text
      _invalid -> nil
    end
  end
end
