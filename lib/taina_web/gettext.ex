defmodule TainaWeb.Gettext do
  @moduledoc """
  Backend de i18n da UI. O idioma padrão é pt-BR (RFC 002, comunidade-first,
  pt-BR primeiro); os textos no código são as `msgid` em português e novos
  idiomas entram como `.po` em `priv/gettext/<locale>`.
  """

  use Gettext.Backend, otp_app: :taina
end
