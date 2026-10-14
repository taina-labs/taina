defmodule TainaWeb.API.Fatia1Test do
  use TainaWeb.ConnCase, async: true

  import Taina.Fixtures

  alias Taina.Scope
  alias Taina.Ybira

  @moduletag capture_log: true

  defp upload(path, filename \\ "doc.txt") do
    %Plug.Upload{path: path, filename: filename, content_type: "text/plain"}
  end

  describe "GET /api/v1/instance" do
    test "caixa virgem: nao bootstrapped, sem Tekoa, com a versao", %{conn: conn} do
      body = conn |> get(~p"/api/v1/instance") |> json_response(200)

      assert body["bootstrapped"] == false
      assert body["tekoa"] == nil
      assert is_binary(body["version"])
    end

    test "com Tekoa criada: devolve a comunidade", %{conn: conn} do
      tekoa = tekoa_fixture()

      body = conn |> get(~p"/api/v1/instance") |> json_response(200)

      assert body["bootstrapped"] == true
      assert body["tekoa"]["public_id"] == tekoa.public_id
      assert body["tekoa"]["domain"] == tekoa.domain
      assert body["tekoa"]["storage_quota_bytes"] == tekoa.storage_quota_bytes
    end

    test "nao exige auth", %{conn: conn} do
      tekoa_fixture()
      assert conn |> get(~p"/api/v1/instance") |> json_response(200)
    end
  end

  describe "sessao por token de dispositivo" do
    setup %{conn: conn} do
      tekoa = tekoa_fixture()
      ava = active_ava_fixture(tekoa)
      %{conn: conn, tekoa: tekoa, ava: ava}
    end

    test "login valido devolve 201 com o segredo cru uma unica vez", %{conn: conn, tekoa: tekoa, ava: ava} do
      body =
        conn
        |> post(~p"/api/v1/session", %{"username" => ava.username, "password" => "senhasegura123"})
        |> json_response(201)

      assert String.starts_with?(body["token"], "tnd_")
      assert body["me"]["public_id"] == ava.public_id
      assert body["tekoa"]["public_id"] == tekoa.public_id
      assert body["device"]["name"] == "Dispositivo"
      assert body["device"]["revoked_at"] == nil
    end

    test "usa o rotulo do aparelho quando o cliente manda", %{conn: conn, ava: ava} do
      body =
        conn
        |> post(~p"/api/v1/session", %{
          "username" => ava.username,
          "password" => "senhasegura123",
          "device_name" => "iPhone da Ana"
        })
        |> json_response(201)

      assert body["device"]["name"] == "iPhone da Ana"
    end

    test "rotulo de aparelho longo e truncado, sem derrubar o login", %{conn: conn, ava: ava} do
      body =
        conn
        |> post(~p"/api/v1/session", %{
          "username" => ava.username,
          "password" => "senhasegura123",
          "device_name" => String.duplicate("a", 200)
        })
        |> json_response(201)

      assert body["device"]["name"] == String.duplicate("a", 80)
    end

    test "senha errada responde 401 no envelope", %{conn: conn, ava: ava} do
      body =
        conn
        |> post(~p"/api/v1/session", %{"username" => ava.username, "password" => "errada"})
        |> json_response(401)

      assert body["error"]["code"] == "invalid_credentials"
      assert is_binary(body["error"]["message"])
    end

    test "conta desativada responde 403, nao 401", %{conn: conn, tekoa: tekoa, ava: ava} do
      zelador = zelador_fixture(tekoa)
      {:ok, _} = Taina.Maraca.deactivate_member(Scope.new(zelador, tekoa), ava.public_id)

      body =
        conn
        |> post(~p"/api/v1/session", %{"username" => ava.username, "password" => "senhasegura123"})
        |> json_response(403)

      assert body["error"]["code"] == "account_deactivated"
    end

    test "GET /me devolve pessoa, Tekoa e dispositivo", %{conn: conn, tekoa: tekoa, ava: ava} do
      body =
        conn
        |> authorize_device(ava)
        |> get(~p"/api/v1/me")
        |> json_response(200)

      assert body["ava"]["public_id"] == ava.public_id
      assert body["tekoa"]["public_id"] == tekoa.public_id
      assert body["device"]["name"] == "teste"
    end

    test "sem Bearer responde 401", %{conn: conn} do
      body = conn |> get(~p"/api/v1/me") |> json_response(401)
      assert body["error"]["code"] == "not_authenticated"
    end

    test "Bearer lixo responde 401", %{conn: conn} do
      conn = put_req_header(conn, "authorization", "Bearer tnd_nao_existe")
      assert conn |> get(~p"/api/v1/me") |> json_response(401)
    end

    test "a sessao de cookie nao autentica a API", %{conn: conn, ava: ava} do
      body = conn |> log_in(ava) |> get(~p"/api/v1/me") |> json_response(401)
      assert body["error"]["code"] == "not_authenticated"
    end

    test "logout revoga o dispositivo; a requisicao seguinte responde 401", %{conn: conn, ava: ava} do
      conn = authorize_device(conn, ava)

      assert conn |> delete(~p"/api/v1/session") |> response(204)
      assert conn |> get(~p"/api/v1/me") |> json_response(401)
    end
  end

  describe "pastas e conteudo" do
    setup %{conn: conn} do
      tekoa = tekoa_fixture()
      ava = active_ava_fixture(tekoa)
      %{conn: authorize_device(conn, ava), ava: ava, tekoa: tekoa}
    end

    test "lista vazia e paginada", %{conn: conn} do
      body = conn |> get(~p"/api/v1/folders") |> json_response(200)
      assert body == %{"items" => [], "next_cursor" => nil}
    end

    test "cria pasta e a devolve no indice e no conteudo", %{conn: conn} do
      created =
        conn
        |> post(~p"/api/v1/folders", %{"name" => "Documentos"})
        |> json_response(201)

      assert created["name"] == "Documentos"
      assert created["zona"] == "casa"
      assert created["rkey"]

      index = conn |> get(~p"/api/v1/folders") |> json_response(200)
      assert Enum.map(index["items"], & &1["rkey"]) == [created["rkey"]]

      contents = conn |> get(~p"/api/v1/contents") |> json_response(200)
      assert Enum.map(contents["folders"], & &1["rkey"]) == [created["rkey"]]
      assert contents["items"] == []
      assert contents["next_cursor"] == nil
    end

    test "pasta inexistente responde 404", %{conn: conn} do
      body = conn |> get(~p"/api/v1/contents?folder=zzzzzzzzzzzzz") |> json_response(404)
      assert body["error"]["code"] == "not_found"
    end

    test "nome vazio responde 422 com details em pt-BR", %{conn: conn} do
      body = conn |> post(~p"/api/v1/folders", %{"name" => ""}) |> json_response(422)
      assert body["error"]["code"] == "validation_failed"
      assert body["error"]["details"]["nome"] == ["não pode ficar em branco"]
    end
  end

  describe "arquivos: subir, ver, baixar" do
    setup %{conn: conn} do
      tekoa = tekoa_fixture()
      ava = active_ava_fixture(tekoa)
      %{conn: authorize_device(conn, ava), ava: ava, tekoa: tekoa}
    end

    test "upload devolve 201 com o sha256 e mime", %{conn: conn} do
      body =
        conn
        |> post(~p"/api/v1/files", %{"file" => upload(tmp_upload_fixture("ola taina", "nota.txt"), "nota.txt")})
        |> json_response(201)

      assert body["name"] == "nota.txt"
      assert body["mime"] == "text/plain"
      assert body["size"] == byte_size("ola taina")
      assert is_binary(body["sha256"])
      assert body["zona"] == "casa"
      assert is_binary(body["rkey"])
    end

    test "upload com destino numa pasta", %{conn: conn} do
      folder = conn |> post(~p"/api/v1/folders", %{"name" => "Fotos"}) |> json_response(201)

      body =
        conn
        |> post(~p"/api/v1/files", %{
          "file" => upload(tmp_upload_fixture("x", "a.txt")),
          "folder" => folder["rkey"]
        })
        |> json_response(201)

      assert body["folder"] == folder["rkey"]
    end

    test "sem a parte do arquivo responde 422 missing_file", %{conn: conn} do
      body = conn |> post(~p"/api/v1/files", %{}) |> json_response(422)
      assert body["error"]["code"] == "missing_file"
    end

    test "mime fora da allowlist responde 422", %{conn: conn} do
      # Magic bytes de um ELF (binario): a deteccao e por conteudo, nao por nome.
      elf = tmp_upload_fixture(<<0x7F, "ELF", 1, 1, 1, 0, 0, 0>>, "run.bin")

      body =
        conn
        |> post(~p"/api/v1/files", %{"file" => upload(elf, "run.bin")})
        |> json_response(422)

      assert body["error"]["code"] == "mime_not_allowed"
    end

    test "cota estourada responde 409", %{conn: conn, tekoa: tekoa} do
      zelador = zelador_fixture(tekoa)
      {:ok, _} = Taina.Maraca.update_tekoa_quota(Scope.new(zelador, tekoa), 1)

      body =
        conn
        |> post(~p"/api/v1/files", %{"file" => upload(tmp_upload_fixture("grande demais"))})
        |> json_response(409)

      assert body["error"]["code"] == "storage_quota_exceeded"
    end

    test "metadado, download e Range", %{conn: conn} do
      file =
        conn
        |> post(~p"/api/v1/files", %{"file" => upload(tmp_upload_fixture("0123456789", "n.txt"))})
        |> json_response(201)

      meta = conn |> get(~p"/api/v1/files/#{file["rkey"]}") |> json_response(200)
      assert meta["rkey"] == file["rkey"]

      download = get(conn, ~p"/api/v1/files/#{file["rkey"]}/download")
      assert download.status == 200
      assert download.resp_body == "0123456789"
      assert get_resp_header(download, "accept-ranges") == ["bytes"]

      range =
        conn
        |> put_req_header("range", "bytes=2-4")
        |> get(~p"/api/v1/files/#{file["rkey"]}/download")

      assert range.status == 206
      assert range.resp_body == "234"
      assert get_resp_header(range, "content-range") == ["bytes 2-4/10"]
    end

    test "Range fora do arquivo responde 416", %{conn: conn} do
      file =
        conn
        |> post(~p"/api/v1/files", %{"file" => upload(tmp_upload_fixture("curto", "c.txt"))})
        |> json_response(201)

      conn = put_req_header(conn, "range", "bytes=100-200")
      response = get(conn, ~p"/api/v1/files/#{file["rkey"]}/download")

      assert response.status == 416
      assert get_resp_header(response, "content-range") == ["bytes */5"]
    end

    test "miniatura de imagem responde webp", %{conn: conn} do
      file =
        conn
        |> post(~p"/api/v1/files", %{"file" => upload(tmp_image_fixture(filename: "p.jpg"), "p.jpg")})
        |> json_response(201)

      response = get(conn, ~p"/api/v1/files/#{file["rkey"]}/thumbnail/sm")

      assert response.status == 200
      assert get_resp_header(response, "content-type") == ["image/webp"]
    end

    test "miniatura de tamanho desconhecido responde 404 no envelope", %{conn: conn} do
      file =
        conn
        |> post(~p"/api/v1/files", %{"file" => upload(tmp_upload_fixture("x", "x.txt"))})
        |> json_response(201)

      body = conn |> get(~p"/api/v1/files/#{file["rkey"]}/thumbnail/xl") |> json_response(404)
      assert body["error"]["code"] == "not_found"
    end

    test "arquivo sem rendition responde 404 no envelope, nao corpo vazio", %{conn: conn} do
      # Achado contra uma caixa de verdade: a miniatura saia por
      # `send_resp(404, "")`, sem envelope, e o cliente caia no fallback
      # `internal_error`.
      file =
        conn
        |> post(~p"/api/v1/files", %{"file" => upload(tmp_upload_fixture("so texto", "nota.txt"))})
        |> json_response(201)

      body = conn |> get(~p"/api/v1/files/#{file["rkey"]}/thumbnail/sm") |> json_response(404)
      assert body["error"]["code"] == "not_found"
    end

    test "Accept de outro tipo nao derruba rota JSON", %{conn: conn} do
      # O pipeline da API nao negocia por `Accept`: o tipo e por rota. Antes,
      # um cliente que pedia `image/webp` levava 406 em toda rota, cortado
      # antes do controller e com `code: internal_error`.
      conn = put_req_header(conn, "accept", "image/webp")

      assert conn |> get(~p"/api/v1/me") |> json_response(200)
    end

    test "Accept de outro tipo tambem nao derruba a miniatura", %{conn: conn} do
      file =
        conn
        |> post(~p"/api/v1/files", %{"file" => upload(tmp_image_fixture(filename: "p.jpg"), "p.jpg")})
        |> json_response(201)

      conn = put_req_header(conn, "accept", "image/webp")
      response = get(conn, ~p"/api/v1/files/#{file["rkey"]}/thumbnail/sm")

      assert response.status == 200
      assert get_resp_header(response, "content-type") == ["image/webp"]
    end

    test "rkey inexistente responde 404", %{conn: conn} do
      body = conn |> get(~p"/api/v1/files/zzzzzzzzzzzzz") |> json_response(404)
      assert body["error"]["code"] == "not_found"
    end
  end

  describe "zonas casa/praca sobre a API" do
    setup %{conn: conn} do
      tekoa = tekoa_fixture()
      dono = active_ava_fixture(tekoa)
      outro = active_ava_fixture(tekoa)
      zelador = zelador_fixture(tekoa)

      {:ok, arquivo} = Ybira.upload(Scope.new(dono, tekoa), tmp_upload_fixture("segredo", "casa.txt"))

      %{
        conn: conn,
        tekoa: tekoa,
        dono: dono,
        outro: outro,
        zelador: zelador,
        arquivo: arquivo
      }
    end

    test "o dono le o proprio arquivo de casa", %{conn: conn, dono: dono, arquivo: arquivo} do
      assert conn
             |> authorize_device(dono)
             |> get(~p"/api/v1/files/#{arquivo.rkey}")
             |> json_response(200)
    end

    test "outro morador recebe 403 no metadado, no download e na miniatura", %{
      conn: conn,
      outro: outro,
      arquivo: arquivo
    } do
      conn = authorize_device(conn, outro)

      assert conn |> get(~p"/api/v1/files/#{arquivo.rkey}") |> json_response(403)
      assert conn |> get(~p"/api/v1/files/#{arquivo.rkey}/download") |> json_response(403)
      assert conn |> get(~p"/api/v1/files/#{arquivo.rkey}/thumbnail/sm") |> json_response(403)
    end

    test "a zeladora nao tem atalho para a casa de ninguem", %{conn: conn, zelador: zelador, arquivo: arquivo} do
      conn = authorize_device(conn, zelador)

      body = conn |> get(~p"/api/v1/files/#{arquivo.rkey}") |> json_response(403)
      assert body["error"]["code"] == "forbidden"
    end

    test "o arquivo de casa de outro nao aparece no conteudo nem na lista", %{
      conn: conn,
      outro: outro,
      arquivo: arquivo
    } do
      conn = authorize_device(conn, outro)

      contents = conn |> get(~p"/api/v1/contents") |> json_response(200)
      refute Enum.any?(contents["items"], &(&1["rkey"] == arquivo.rkey))
    end

    test "publicar na praca libera a leitura para o outro morador", %{
      conn: conn,
      tekoa: tekoa,
      dono: dono,
      outro: outro,
      arquivo: arquivo
    } do
      {:ok, _} = Ybira.publicar_file(Scope.new(dono, tekoa), arquivo.rkey)

      conn = authorize_device(conn, outro)
      body = conn |> get(~p"/api/v1/files/#{arquivo.rkey}") |> json_response(200)
      assert body["zona"] == "praca"
    end

    test "404 e 403 sao distintos", %{conn: conn, outro: outro} do
      conn = authorize_device(conn, outro)

      assert conn |> get(~p"/api/v1/files/zzzzzzzzzzzzz") |> json_response(404)
    end
  end
end
