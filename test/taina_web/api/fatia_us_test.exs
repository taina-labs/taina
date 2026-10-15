defmodule TainaWeb.API.FatiaUsTest do
  use TainaWeb.ConnCase, async: true

  import Taina.Fixtures

  alias Taina.Scope
  alias Taina.Ybira

  @moduletag capture_log: true

  defp upload(path, filename) do
    %Plug.Upload{path: path, filename: filename, content_type: "text/plain"}
  end

  describe "pessoas e convites" do
    setup %{conn: conn} do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      morador = active_ava_fixture(tekoa)
      %{conn: conn, tekoa: tekoa, zelador: zelador, morador: morador}
    end

    test "a lista de pessoas e de qualquer morador, zeladora primeiro", %{
      conn: conn,
      morador: morador,
      zelador: zelador
    } do
      body = conn |> authorize_device(morador) |> get(~p"/api/v1/members") |> json_response(200)
      assert Enum.map(body["items"], & &1["public_id"]) == [zelador.public_id, morador.public_id]
      assert body["next_cursor"] == nil
    end

    test "so a zeladora convida", %{conn: conn, zelador: zelador, morador: morador} do
      body = conn |> authorize_device(morador) |> post(~p"/api/v1/members", %{}) |> json_response(403)
      assert body["error"]["code"] == "not_zelador"

      created =
        conn
        |> authorize_device(zelador)
        |> post(~p"/api/v1/members", %{"papel" => "morador"})
        |> json_response(201)

      assert String.starts_with?(created["invite_url"], "taina://convite/#{created["token"]}?host=")
    end

    test "papel explicito desconhecido no convite responde 422", %{conn: conn, zelador: zelador} do
      body =
        conn
        |> authorize_device(zelador)
        |> post(~p"/api/v1/members", %{"papel" => "curador"})
        |> json_response(422)

      assert body["error"]["code"] == "invalid_action"
    end

    test "a zeladora muda o papel e desativa", %{conn: conn, zelador: zelador, morador: morador} do
      conn = authorize_device(conn, zelador)

      promoted =
        conn
        |> patch(~p"/api/v1/members/#{morador.public_id}", %{"papel" => "zelador"})
        |> json_response(200)

      assert promoted["papel"] == "zelador"

      assert conn |> delete(~p"/api/v1/members/#{morador.public_id}") |> response(204)
      assert conn |> post(~p"/api/v1/members/#{morador.public_id}/reactivate") |> json_response(200)
    end

    test "o link de senha volta so pela zeladora", %{conn: conn, zelador: zelador, morador: morador} do
      body =
        conn
        |> authorize_device(zelador)
        |> post(~p"/api/v1/members/#{morador.public_id}/reset-link")
        |> json_response(201)

      assert String.starts_with?(body["reset_url"], "taina://redefinir/")
    end
  end

  describe "dispositivos" do
    test "lista os proprios e revoga so com permissao", %{conn: conn} do
      tekoa = tekoa_fixture()
      ana = active_ava_fixture(tekoa)
      bia = active_ava_fixture(tekoa)

      ana_conn = authorize_device(conn, ana)
      bia_conn = authorize_device(conn, bia)

      list = ana_conn |> get(~p"/api/v1/devices") |> json_response(200)
      assert length(list["items"]) == 1
      device = hd(list["items"])

      forbidden = bia_conn |> delete(~p"/api/v1/devices/#{device["public_id"]}") |> json_response(403)
      assert forbidden["error"]["code"] == "unauthorized"

      assert ana_conn |> delete(~p"/api/v1/devices/#{device["public_id"]}") |> response(204)
    end
  end

  describe "pastas: mutacoes" do
    setup %{conn: conn} do
      tekoa = tekoa_fixture()
      ava = active_ava_fixture(tekoa)
      {:ok, conn: authorize_device(conn, ava), tekoa: tekoa, ava: ava}
    end

    test "renomear, publicar e voltar para a casa", %{conn: conn} do
      folder = conn |> post(~p"/api/v1/folders", %{"name" => "Rascunho"}) |> json_response(201)

      renamed = conn |> patch(~p"/api/v1/folders/#{folder["rkey"]}", %{"name" => "Final"}) |> json_response(200)
      assert renamed["name"] == "Final"

      published = conn |> patch(~p"/api/v1/folders/#{folder["rkey"]}", %{"zona" => "praca"}) |> json_response(200)
      assert published["zona"] == "praca"

      back = conn |> patch(~p"/api/v1/folders/#{folder["rkey"]}", %{"zona" => "casa"}) |> json_response(200)
      assert back["zona"] == "casa"
    end

    test "mover para dentro de outra pasta e apagar", %{conn: conn} do
      parent = conn |> post(~p"/api/v1/folders", %{"name" => "Guarda"}) |> json_response(201)
      child = conn |> post(~p"/api/v1/folders", %{"name" => "Dentro"}) |> json_response(201)

      moved =
        conn
        |> post(~p"/api/v1/folders/#{child["rkey"]}/move", %{"parent_rkey" => parent["rkey"]})
        |> json_response(200)

      assert moved["folder"] == parent["rkey"]

      assert conn |> delete(~p"/api/v1/folders/#{child["rkey"]}") |> response(204)
    end

    test "mover para dentro de si mesma responde 409", %{conn: conn} do
      folder = conn |> post(~p"/api/v1/folders", %{"name" => "Ciclo"}) |> json_response(201)

      body =
        conn
        |> post(~p"/api/v1/folders/#{folder["rkey"]}/move", %{"parent_rkey" => folder["rkey"]})
        |> json_response(409)

      assert body["error"]["code"] == "circular_reference"
    end
  end

  describe "arquivos: mutacoes, recentes e lixeira" do
    setup %{conn: conn} do
      tekoa = tekoa_fixture()
      ava = active_ava_fixture(tekoa)
      {:ok, conn: authorize_device(conn, ava), tekoa: tekoa, ava: ava}
    end

    test "renomear, publicar, mover e apagar", %{conn: conn} do
      folder = conn |> post(~p"/api/v1/folders", %{"name" => "Destino"}) |> json_response(201)

      file =
        conn
        |> post(~p"/api/v1/files", %{"file" => upload(tmp_upload_fixture("x", "a.txt"), "a.txt")})
        |> json_response(201)

      renamed = conn |> patch(~p"/api/v1/files/#{file["rkey"]}", %{"name" => "b.txt"}) |> json_response(200)
      assert renamed["name"] == "b.txt"

      published = conn |> patch(~p"/api/v1/files/#{file["rkey"]}", %{"zona" => "praca"}) |> json_response(200)
      assert published["zona"] == "praca"

      moved =
        conn
        |> post(~p"/api/v1/files/#{file["rkey"]}/move", %{"folder" => folder["rkey"]})
        |> json_response(200)

      assert moved["folder"] == folder["rkey"]

      assert conn |> delete(~p"/api/v1/files/#{file["rkey"]}") |> response(204)
    end

    test "os recentes trazem o que subiu", %{conn: conn} do
      file =
        conn
        |> post(~p"/api/v1/files", %{"file" => upload(tmp_upload_fixture("x", "r.txt"), "r.txt")})
        |> json_response(201)

      body = conn |> get(~p"/api/v1/recent") |> json_response(200)
      assert Enum.any?(body["items"], &(&1["rkey"] == file["rkey"]))
    end

    test "apagar manda para a lixeira e restaurar volta", %{conn: conn} do
      file =
        conn
        |> post(~p"/api/v1/files", %{"file" => upload(tmp_upload_fixture("x", "t.txt"), "t.txt")})
        |> json_response(201)

      assert conn |> delete(~p"/api/v1/files/#{file["rkey"]}") |> response(204)

      trash = conn |> get(~p"/api/v1/trash") |> json_response(200)
      assert Enum.any?(trash["items"], &(&1["rkey"] == file["rkey"]))

      restored = conn |> post(~p"/api/v1/trash/#{file["rkey"]}/restore") |> json_response(200)
      assert restored["deleted_at"] == nil
    end
  end

  describe "fotos" do
    setup %{conn: conn} do
      tekoa = tekoa_fixture()
      ava = active_ava_fixture(tekoa)
      {:ok, conn: authorize_device(conn, ava), tekoa: tekoa, ava: ava}
    end

    test "a grade e a linha do tempo mostram a imagem", %{conn: conn} do
      photo =
        conn
        |> post(~p"/api/v1/files", %{"file" => upload(tmp_image_fixture(filename: "f.jpg"), "f.jpg")})
        |> json_response(201)

      grid = conn |> get(~p"/api/v1/photos") |> json_response(200)
      assert Enum.any?(grid["items"], &(&1["rkey"] == photo["rkey"]))

      timeline = conn |> get(~p"/api/v1/photos/timeline") |> json_response(200)
      assert [%{"date" => date, "photos" => photos} | _] = timeline["items"]
      assert is_binary(date)
      assert Enum.any?(photos, &(&1["rkey"] == photo["rkey"]))
    end
  end

  describe "pedidos de acesso" do
    setup %{conn: conn} do
      tekoa = tekoa_fixture()
      dono = active_ava_fixture(tekoa)
      outro = active_ava_fixture(tekoa)
      {:ok, file} = Ybira.upload(Scope.new(dono, tekoa), tmp_upload_fixture("segredo", "casa.txt"))
      {:ok, conn: conn, tekoa: tekoa, dono: dono, outro: outro, arquivo: file}
    end

    test "descobrir o dono e pedir", %{conn: conn, dono: dono, outro: outro, arquivo: arquivo} do
      conn = authorize_device(conn, outro)

      target = conn |> get(~p"/api/v1/files/#{arquivo.rkey}/access-target") |> json_response(200)
      assert target["owner"]["public_id"] == dono.public_id

      pedido =
        conn
        |> post(~p"/api/v1/files/#{arquivo.rkey}/access-request", %{"motivo" => "preciso ver"})
        |> json_response(201)

      assert pedido["status"] == "pendente"

      mine = conn |> get(~p"/api/v1/my-requests") |> json_response(200)
      assert Enum.any?(mine["items"], &(&1["public_id"] == pedido["public_id"]))
    end

    test "quem ja le recebe 409 no alvo", %{conn: conn, dono: dono, arquivo: arquivo} do
      body =
        conn
        |> authorize_device(dono)
        |> get(~p"/api/v1/files/#{arquivo.rkey}/access-target")
        |> json_response(409)

      assert body["error"]["code"] == "already_readable"
    end

    test "a dona aprova e o outro passa a ler", %{conn: conn, dono: dono, outro: outro, arquivo: arquivo} do
      pedido =
        conn
        |> authorize_device(outro)
        |> post(~p"/api/v1/files/#{arquivo.rkey}/access-request", %{"motivo" => "por favor"})
        |> json_response(201)

      dono_conn = authorize_device(conn, dono)
      recebidos = dono_conn |> get(~p"/api/v1/access-requests") |> json_response(200)
      assert Enum.any?(recebidos["items"], &(&1["public_id"] == pedido["public_id"]))

      concessao =
        dono_conn
        |> post(~p"/api/v1/access-requests/#{pedido["public_id"]}/approve")
        |> json_response(200)

      assert concessao["recurso"] == arquivo.rkey

      assert conn
             |> authorize_device(outro)
             |> get(~p"/api/v1/files/#{arquivo.rkey}")
             |> json_response(200)
    end

    test "a dona nega", %{conn: conn, dono: dono, outro: outro, arquivo: arquivo} do
      pedido =
        conn
        |> authorize_device(outro)
        |> post(~p"/api/v1/files/#{arquivo.rkey}/access-request", %{"motivo" => "quem sabe"})
        |> json_response(201)

      negado =
        conn
        |> authorize_device(dono)
        |> post(~p"/api/v1/access-requests/#{pedido["public_id"]}/deny")
        |> json_response(200)

      assert negado["status"] == "negado"
    end
  end

  describe "mural, armazenamento e saude" do
    setup %{conn: conn} do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      morador = active_ava_fixture(tekoa)
      %{conn: conn, tekoa: tekoa, zelador: zelador, morador: morador}
    end

    test "o mural projeta a cadeia", %{conn: conn, zelador: zelador} do
      conn = authorize_device(conn, zelador)
      assert conn |> post(~p"/api/v1/members", %{}) |> json_response(201)

      body = conn |> get(~p"/api/v1/mural") |> json_response(200)
      assert is_list(body["items"])
      assert Enum.any?(body["items"], &(&1["tipo"] == "invite_created"))
    end

    test "o retrato do armazenamento", %{conn: conn, morador: morador} do
      body = conn |> authorize_device(morador) |> get(~p"/api/v1/storage") |> json_response(200)

      assert body["quota_bytes"] > 0
      assert is_integer(body["used_bytes"])
      assert %{"photos" => _, "others" => _} = body["by_kind"]
      assert %{"count" => _, "bytes" => _} = body["trash"]
    end

    test "so a zeladora muda a cota", %{conn: conn, zelador: zelador, morador: morador} do
      body =
        conn
        |> authorize_device(morador)
        |> patch(~p"/api/v1/storage/quota", %{"quota_bytes" => 1_000})
        |> json_response(403)

      assert body["error"]["code"] == "not_zelador"

      updated =
        conn
        |> authorize_device(zelador)
        |> patch(~p"/api/v1/storage/quota", %{"quota_bytes" => 1_000})
        |> json_response(200)

      assert updated["storage_quota_bytes"] == 1_000
    end

    test "a saude traz armazenamento, jobs e backup", %{conn: conn, morador: morador} do
      body = conn |> authorize_device(morador) |> get(~p"/api/v1/saude") |> json_response(200)

      assert %{"used_bytes" => _} = body["storage"]
      assert %{"renditions" => _, "trash_purge" => _} = body["jobs"]
      assert %{"at" => _, "bytes" => _} = body["backup"]
    end

    test "so a zeladora dispara o backup", %{conn: conn, zelador: zelador, morador: morador} do
      conn |> authorize_device(morador) |> post(~p"/api/v1/saude/backup") |> json_response(403)

      body =
        conn
        |> authorize_device(zelador)
        |> post(~p"/api/v1/saude/backup")
        |> json_response(202)

      assert body["scheduled"] == true
    end
  end
end
