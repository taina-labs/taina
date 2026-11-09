defmodule TainaWeb.InviteLink do
  @moduledoc false

  def deep_link(token) when is_binary(token) do
    "taina://convite/#{token}?host=#{URI.encode_www_form(TainaWeb.Endpoint.url())}"
  end
end
