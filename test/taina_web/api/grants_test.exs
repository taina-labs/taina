defmodule TainaWeb.API.GrantsTest do
  use TainaWeb.ConnCase, async: true

  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Scope
  alias Taina.Ybira

  @moduletag capture_log: true

  setup do
    tekoa = tekoa_fixture()
    dono = active_ava_fixture(tekoa)
    leitor = active_ava_fixture(tekoa)

    {:ok, file} = Ybira.upload(Scope.new(dono, tekoa), tmp_upload_fixture("segredo", "casa.txt"))
    {:ok, _concessao} = Maraca.conceder(Scope.new(dono, tekoa), "ypy.file.v0", file.rkey, leitor)

    %{
      tekoa: tekoa,
      dono: dono,
      leitor: leitor,
      conn: authorize_device(build_conn(), dono),
      leitor_conn: authorize_device(build_conn(), leitor)
    }
  end

  describe "GET /api/v1/grants" do
    test "a dona ve o que concedeu, com quem le", %{conn: conn, dono: dono, leitor: leitor} do
      body = conn |> get(~p"/api/v1/grants") |> json_response(200)

      assert [item] = body["items"]
      assert body["next_cursor"] == nil
      assert item["dono"]["public_id"] == dono.public_id
      assert item["leitor"]["public_id"] == leitor.public_id
      assert item["revogada_em"] == nil
    end

    test "quem recebeu ve a ponta do leitor, com a dona", %{leitor_conn: leitor_conn, dono: dono, leitor: leitor} do
      body = leitor_conn |> get(~p"/api/v1/grants", role: "reader") |> json_response(200)

      assert [item] = body["items"]
      assert item["dono"]["public_id"] == dono.public_id
      assert item["leitor"]["public_id"] == leitor.public_id
    end

    test "revogada segue no espelho, com a data da revogacao", %{conn: conn} do
      assert [item] = conn |> get(~p"/api/v1/grants") |> json_response(200) |> Map.get("items")

      assert conn |> delete(~p"/api/v1/grants/#{item["public_id"]}") |> response(204)

      body = conn |> get(~p"/api/v1/grants") |> json_response(200)
      assert [%{"revogada_em" => revogada_em}] = body["items"]
      assert is_binary(revogada_em)
    end

    test "papel desconhecido cai na ponta da dona", %{conn: conn} do
      body = conn |> get(~p"/api/v1/grants", role: "qualquer") |> json_response(200)
      assert length(body["items"]) == 1
    end

    test "o ETag bate de novo: 304 sem corpo", %{conn: conn} do
      first = get(conn, ~p"/api/v1/grants")

      etag =
        Enum.find_value(first.resp_headers, fn {k, v} -> k == "etag" && v end)

      assert is_binary(etag)

      response =
        conn
        |> put_req_header("if-none-match", etag)
        |> get(~p"/api/v1/grants")

      assert response.status == 304
      assert response.resp_body == ""
    end
  end

  describe "DELETE /api/v1/grants/:public_id" do
    test "a dona revoga: 204 e a casa fecha", %{conn: conn, leitor_conn: leitor_conn} do
      assert [item] = conn |> get(~p"/api/v1/grants") |> json_response(200) |> Map.get("items")

      assert conn |> delete(~p"/api/v1/grants/#{item["public_id"]}") |> response(204)

      body = leitor_conn |> get(~p"/api/v1/grants", role: "reader") |> json_response(200)
      assert [%{"revogada_em" => revogada_em}] = body["items"]
      assert is_binary(revogada_em)
    end

    test "revogar de novo responde 409 invalid_status", %{conn: conn} do
      assert [item] = conn |> get(~p"/api/v1/grants") |> json_response(200) |> Map.get("items")
      assert conn |> delete(~p"/api/v1/grants/#{item["public_id"]}") |> response(204)

      body = conn |> delete(~p"/api/v1/grants/#{item["public_id"]}") |> json_response(409)
      assert body["error"]["code"] == "invalid_status"
    end

    test "quem recebeu nao revoga: 403", %{conn: conn, leitor_conn: leitor_conn} do
      assert [item] = conn |> get(~p"/api/v1/grants") |> json_response(200) |> Map.get("items")

      # O kernel guarda com :not_authorized (o atomo do fio), nao :not_owner
      # como o contrato C4 escreveu; 403 dos dois jeitos. Desvio do contrato
      # reportado ao orchestrador.
      body = leitor_conn |> delete(~p"/api/v1/grants/#{item["public_id"]}") |> json_response(403)
      assert body["error"]["code"] == "not_authorized"
    end

    test "public_id desconhecido responde 404", %{conn: conn} do
      body = conn |> delete(~p"/api/v1/grants/nao-existe") |> json_response(404)
      assert body["error"]["code"] == "not_found"
    end
  end
end
