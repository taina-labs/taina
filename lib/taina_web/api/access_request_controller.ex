defmodule TainaWeb.API.AccessRequestController do
  @moduledoc """
  Os pedidos de acesso (RFC_005 secao 9): os recebidos (eu sou o dono), os
  enviados, e a decisao do dono (aprovar gera a concessao, negar fecha o
  pedido).
  """

  use TainaWeb, :controller

  alias Taina.Maraca
  alias TainaWeb.API.Error
  alias TainaWeb.API.Serializer
  alias Ypy.Wire

  def index(conn, _params) do
    case Maraca.pedidos_recebidos(conn.assigns[:current_scope]) do
      {:ok, pedidos} -> json(conn, page(pedidos))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def mine(conn, _params) do
    case Maraca.pedidos_enviados(conn.assigns[:current_scope]) do
      {:ok, pedidos} -> json(conn, page(pedidos))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def approve(conn, %{"id" => id}) do
    scope = conn.assigns[:current_scope]

    with {:ok, pedido} <- Maraca.get_pedido(scope, id),
         {:ok, concessao} <- Maraca.aprovar(scope, pedido) do
      json(conn, Serializer.concessao(concessao))
    else
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def deny(conn, %{"id" => id}) do
    scope = conn.assigns[:current_scope]

    with {:ok, pedido} <- Maraca.get_pedido(scope, id),
         {:ok, decidido} <- Maraca.negar(scope, pedido) do
      json(conn, Serializer.pedido(decidido))
    else
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  defp page(pedidos), do: Wire.page(Enum.map(pedidos, &Serializer.pedido/1), nil)
end
