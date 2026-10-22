defmodule TainaWeb.API.EtagTest do
  use TainaWeb.ConnCase, async: true

  import Plug.Conn

  alias TainaWeb.API.Etag

  @moduletag capture_log: true

  test "o token leva a contagem e o unix do maior updated_at" do
    at = ~U[2026-10-20 12:30:00Z]

    assert Etag.token(0, nil) == ~s(W/"0-0")
    assert Etag.token(3, at) == ~s(W/"3-#{DateTime.to_unix(at)}")
  end

  test "sem If-None-Match, a listagem segue com o ETag anotado" do
    {:fresh, conn} = Etag.handle(build_conn(), ~s(W/"3-10"))

    assert get_resp_header(conn, "etag") == [~s(W/"3-10")]
  end

  test "If-None-Match igual responde 304 sem corpo, com o ETag na resposta" do
    conn = put_req_header(build_conn(), "if-none-match", ~s(W/"3-10"))

    {:not_modified, conn} = Etag.handle(conn, ~s(W/"3-10"))

    assert conn.status == 304
    assert conn.resp_body == ""
    assert get_resp_header(conn, "etag") == [~s(W/"3-10")]
  end

  test "ETag diferente nao bate: a listagem segue" do
    conn = put_req_header(build_conn(), "if-none-match", ~s(W/"9-99"))

    assert {:fresh, _conn} = Etag.handle(conn, ~s(W/"3-10"))
  end

  test "`*` casa com qualquer representacao existente: 304" do
    conn = put_req_header(build_conn(), "if-none-match", "*")

    {:not_modified, conn} = Etag.handle(conn, ~s(W/"3-10"))

    assert conn.status == 304
  end

  test "comparacao fraca: o token sem o `W/` da frente tambem bate" do
    conn = put_req_header(build_conn(), "if-none-match", ~s("3-10"))

    {:not_modified, conn} = Etag.handle(conn, ~s(W/"3-10"))

    assert conn.status == 304
  end

  test "header repetido e com varios tokens: qualquer um que bata faz 304" do
    conn = put_req_header(build_conn(), "if-none-match", ~s(W/"1-1", W/"3-10"))

    {:not_modified, _conn} = Etag.handle(conn, ~s(W/"3-10"))
  end

  describe "agregados (precisa de banco)" do
    import Taina.Fixtures

    alias Taina.Jaci.Photo
    alias Taina.Repo
    alias Taina.Scope
    alias Taina.Ybira

    setup do
      tekoa = tekoa_fixture()
      dono = active_ava_fixture(tekoa)
      %{scope: Scope.new(dono, tekoa)}
    end

    test "a rendicao que muda a foto muda o ETag de fotos (a mesma hora do arquivo nao basta)", %{scope: scope} do
      {:ok, file} = Ybira.upload(scope, tmp_image_fixture(filename: "foto.jpg"))

      # a linha da foto e do WORKER: sempre mais nova que o upload (o
      # carimbo dela tem de dominar o agregado)
      upsert_metadata(file.id, %{"thumbnails" => %{"sm" => "x.webp"}}, ~U[2030-01-01 00:00:00Z])
      antes = Etag.photos(scope)

      # o worker grava a rendition de novo: `jaci_photos.updated_at` muda, o
      # do arquivo nao. O ETag de fotos tem de observar os dois.
      upsert_metadata(file.id, %{"thumbnails" => %{"sm" => "x.webp", "v2" => true}}, ~U[2030-01-02 00:00:00Z])

      refute Etag.photos(scope) == antes
    end

    test "criar subpasta muda o ETag do conteudo da pasta", %{scope: scope} do
      {:ok, folder} = Ybira.create_folder(scope, %{name: "ferias"})
      {:ok, antes} = Etag.folder_files(scope, folder.rkey)

      {:ok, _sub} = Ybira.create_folder(scope, %{name: "praia", parent_rkey: folder.rkey})

      {:ok, depois} = Etag.folder_files(scope, folder.rkey)
      refute antes == depois
    end

    test "a rendicao de uma foto da pasta tambem muda o ETag do conteudo", %{scope: scope} do
      {:ok, folder} = Ybira.create_folder(scope, %{name: "ferias"})
      {:ok, file} = Ybira.upload(scope, tmp_image_fixture(filename: "foto.jpg"), folder_rkey: folder.rkey)

      upsert_metadata(file.id, %{"thumbnails" => %{"sm" => "x.webp"}}, ~U[2030-01-01 00:00:00Z])
      {:ok, antes} = Etag.folder_files(scope, folder.rkey)

      upsert_metadata(file.id, %{"thumbnails" => %{"sm" => "x.webp", "v2" => true}}, ~U[2030-01-02 00:00:00Z])

      {:ok, depois} = Etag.folder_files(scope, folder.rkey)
      refute antes == depois
    end

    # A linha de foto pode ja existir (o worker roda no upload em teste):
    # upsert, com o `updated_at` sob controle do teste -- o carimbo da linha
    # e o que o agregado observa.
    defp upsert_metadata(file_id, metadata, updated_at) do
      %Photo{file_id: file_id}
      |> Photo.changeset(%{metadata: metadata})
      |> Repo.insert!(
        on_conflict: [set: [metadata: metadata, updated_at: updated_at]],
        conflict_target: :file_id,
        skip_tekoa_id: true
      )
    end
  end
end
