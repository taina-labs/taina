defmodule TainaWeb.API.MeController do
  @moduledoc "Quem esta agindo (RFC_005 secao 9): a pessoa, a Tekoa e o dispositivo da chamada."

  use TainaWeb, :controller

  alias TainaWeb.API.Serializer

  def show(conn, _params) do
    json(conn, Serializer.me(conn.assigns[:current_scope], conn.assigns[:api_device]))
  end
end
