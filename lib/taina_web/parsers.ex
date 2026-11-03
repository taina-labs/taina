defmodule TainaWeb.Parsers do
  @moduledoc """
  Plug parser configuration derived from the same upload limit used by Ybira.

  Multipart requests need a small envelope margin around the file bytes. The
  exact blob limit is still enforced by `Taina.Ybira.upload/3`.
  """

  @multipart_overhead 1 * 1024 * 1024

  def init(_opts) do
    Plug.Parsers.init(
      parsers: [:urlencoded, :multipart, :json],
      pass: ["*/*"],
      json_decoder: Phoenix.json_library(),
      multipart: [length: Taina.Ybira.max_blob_size() + @multipart_overhead]
    )
  end

  def call(conn, opts), do: Plug.Parsers.call(conn, opts)
end
