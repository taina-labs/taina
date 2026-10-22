defmodule TainaWeb.API.GrantController do
  @moduledoc """
  As concessoes de acesso pela API (contrato review 0.1.0, C3/C4): o morador
  ve as duas pontas do espelho -- as que concedeu e as que recebeu, revogadas
  incluidas (revogar nao apaga o fato social) -- e revoga as que sao dele.
  """

  use TainaWeb, :controller

  alias Taina.Maraca
  alias Taina.Maraca.Grants
  alias TainaWeb.API.Error
  alias TainaWeb.API.Etag
  alias TainaWeb.API.Query
  alias TainaWeb.API.Serializer
  alias Ypy.Wire

  def index(conn, params) do
    scope = conn.assigns[:current_scope]
    role = parse_role(params["role"])
    opts = [limit: Query.limit(params), after_cursor: Query.after_cursor(params)]

    with {:ok, %{count: count, max_updated_at: last}} <- Grants.stats(scope, role),
         {:fresh, conn} <- Etag.handle(conn, Etag.token(count, last)),
         {:ok, %{items: concessoes, next_cursor: next}} <- concessions(scope, role, opts) do
      json(conn, Wire.page(Enum.map(concessoes, &Serializer.concessao/1), next))
    else
      {:not_modified, conn} -> conn
    end
  end

  def revoke(conn, %{"public_id" => public_id}) do
    scope = conn.assigns[:current_scope]

    with {:ok, concessao} <- Grants.get(scope, public_id),
         {:ok, _concessao} <- Maraca.revogar(scope, concessao) do
      send_resp(conn, 204, "")
    else
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  defp concessions(scope, :owner, opts), do: Grants.concedidas(scope, opts)
  defp concessions(scope, :reader, opts), do: Grants.recebidas(scope, opts)

  # A ponta do espelho: reader e a casa que abriram para quem chama; qualquer
  # outro valor (ou nenhum) e a casa que quem chama abriu, como todo
  # parametro de lista cai no padrao.
  defp parse_role("reader"), do: :reader
  defp parse_role(_role), do: :owner
end
