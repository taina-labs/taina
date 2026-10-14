defmodule TainaWeb.API.MemberController do
  @moduledoc """
  As pessoas da comunidade (RFC_005 secao 9): a lista para todo morador e a
  gestao (convite, papel, desativar, reativar, revogar convite, link de senha)
  so para a zeladora.

  Aceitar o convite e redefinir a senha ficam fora da API (RFC_005 secao 12):
  o app recebe o token e o endereco sai por deep link.
  """

  use TainaWeb, :controller

  alias Taina.Maraca
  alias TainaWeb.API.Error
  alias Ypy.Wire

  def index(conn, _params) do
    case Maraca.list_members(conn.assigns[:current_scope]) do
      {:ok, members} -> json(conn, Wire.page(Enum.map(members, &Wire.Ava.json/1), nil))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def create(conn, params) do
    scope = conn.assigns[:current_scope]

    case Maraca.invite_user(scope.ava, scope.tekoa, role: role(params["papel"])) do
      {:ok, %{ava: ava, token: token}} ->
        conn
        |> put_status(201)
        |> json(%{
          "ava" => Wire.Ava.json(ava),
          "token" => token,
          "invite_url" => "taina://convite/" <> token
        })

      {:error, reason} ->
        Error.reply(conn, reason)
    end
  end

  def update(conn, %{"id" => id} = params) do
    scope = conn.assigns[:current_scope]

    case papel(params["papel"]) do
      {:ok, papel} ->
        case Maraca.update_member_role(scope, id, papel) do
          {:ok, ava} -> json(conn, Wire.Ava.json(ava))
          {:error, reason} -> Error.reply(conn, reason)
        end

      :error ->
        Error.reply(conn, :invalid_action)
    end
  end

  def delete(conn, %{"id" => id}) do
    case Maraca.deactivate_member(conn.assigns[:current_scope], id) do
      {:ok, _ava} -> send_resp(conn, 204, "")
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def reactivate(conn, %{"id" => id}) do
    case Maraca.reactivate_member(conn.assigns[:current_scope], id) do
      {:ok, ava} -> json(conn, Wire.Ava.json(ava))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def revoke_invite(conn, %{"id" => id}) do
    case Maraca.revoke_invite(conn.assigns[:current_scope], id) do
      {:ok, _ava} -> send_resp(conn, 204, "")
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def reset_link(conn, %{"id" => id}) do
    scope = conn.assigns[:current_scope]

    with {:ok, member} <- Maraca.get_member(scope, id),
         {:ok, %{token: token}} <- Maraca.mint_reset_link(scope, member) do
      conn
      |> put_status(201)
      |> json(%{
        "ava" => Wire.Ava.json(member),
        "token" => token,
        "reset_url" => "taina://redefinir/" <> token
      })
    else
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  # Sem papel no corpo, convida como morador (o default do contexto).
  defp role(nil), do: :morador
  defp role("zelador"), do: :zelador
  defp role(_), do: :morador

  defp papel("morador"), do: {:ok, :morador}
  defp papel("zelador"), do: {:ok, :zelador}
  defp papel(_), do: :error
end
