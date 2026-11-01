defmodule TainaWeb.InternalPath do
  @moduledoc false

  def from_uri(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{path: path, query: query} when is_binary(path) ->
        if is_binary(query), do: path <> "?" <> query, else: path

      _invalid_uri ->
        "/"
    end
  end

  def return_to(value, fallback) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: nil, host: nil, path: <<"/", second, _rest::binary>>}
      when second != ?/ and second != ?\\ ->
        if valid_internal_url?(value), do: value, else: fallback

      %URI{scheme: nil, host: nil, path: "/"} ->
        if valid_internal_url?(value), do: value, else: fallback

      _external_or_invalid ->
        fallback
    end
  rescue
    _error -> fallback
  end

  def return_to(_value, fallback), do: fallback

  defp valid_internal_url?(value) do
    not String.contains?(value, "\\") and not Regex.match?(~r/%(?![[:xdigit:]]{2})/, value)
  end
end
