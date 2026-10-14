defmodule TainaWeb.API.AccessController do
  @moduledoc """
  Pedido de acesso a um arquivo de casa (RFC_005 secao 9): quem ainda nao le
  descobre o dono e pede; o pedido e mero intermediario, nao da acesso.
  """

  use TainaWeb, :controller

  alias Taina.Maraca
  alias Taina.Ybira
  alias TainaWeb.API.Error
  alias TainaWeb.API.Serializer

  def show(conn, %{"id" => rkey}) do
    case Ybira.fetch_access_target(conn.assigns[:current_scope], rkey) do
      {:ok, target} -> json(conn, Serializer.access_target(target))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def create(conn, %{"id" => rkey} = params) do
    scope = conn.assigns[:current_scope]

    case Ybira.fetch_access_target(scope, rkey) do
      {:ok, _target} ->
        case Maraca.pedir_acesso(scope, "ypy.file.v0", rkey, params["motivo"]) do
          {:ok, pedido} -> conn |> put_status(201) |> json(Serializer.pedido(pedido))
          {:error, reason} -> Error.reply(conn, reason)
        end

      {:error, reason} ->
        Error.reply(conn, reason)
    end
  end
end
