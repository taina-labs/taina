defmodule Taina.IsolationSweepTest do
  @moduledoc """
  A tripwire que substitui o RLS (RFC_006, secao 11): no SQLite nao existe
  Row-Level Security, entao o isolamento por comunidade e por zona e promessa
  da camada de aplicacao. Esta suite varre toda superficie de leitura e prova,
  superficie por superficie, que:

    * o morador B nao le nada da casa do morador A (arquivo, pasta, foto,
      lixeira, listagens, agregados, download, thumbnail, telas);
    * o zelador nao tem atalho para a casa de ninguem (RFC_003 D2: zero
      autoridade sobre dados);
    * e publicar na praca e o que libera a leitura. So isso.

  Nao ha API JSON de dados hoje (so `/health`); as superficies sao os
  contexts, os controllers de download/thumbnail e os LiveViews. Toda
  superficie nova de leitura precisa nascer com uma linha aqui.
  """

  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Jaci
  alias Taina.Maraca
  alias Taina.Scope
  alias Taina.Ybira

  @casa_contents "conteudo particular do morador A"
  @casa_filename "estatuto-interno.txt"

  setup do
    tekoa = tekoa_fixture()
    owner = active_ava_fixture(tekoa)
    reader = active_ava_fixture(tekoa)
    zelador = zelador_fixture(tekoa)

    owner_scope = Scope.new(owner, tekoa)
    reader_scope = Scope.new(reader, tekoa)
    zelador_scope = Scope.new(zelador, tekoa)

    {:ok, casa_file} = Ybira.upload(owner_scope, tmp_upload_fixture(@casa_contents, @casa_filename))

    %{
      tekoa: tekoa,
      owner: owner,
      reader: reader,
      zelador: zelador,
      owner_scope: owner_scope,
      reader_scope: reader_scope,
      zelador_scope: zelador_scope,
      casa_file: casa_file
    }
  end

  describe "contexts: o morador B nao le a casa do morador A" do
    test "get_file/2 recusa, e a praca libera", ctx do
      assert {:error, :forbidden} = Ybira.get_file(ctx.reader_scope, ctx.casa_file.public_id)

      {:ok, _} = Ybira.publicar_file(ctx.owner_scope, ctx.casa_file.public_id)

      assert {:ok, _} = Ybira.get_file(ctx.reader_scope, ctx.casa_file.public_id)
    end

    test "list_files/3 esconde, e a praca libera", ctx do
      assert {:ok, %{items: []}} = Ybira.list_files(ctx.reader_scope)

      {:ok, _} = Ybira.publicar_file(ctx.owner_scope, ctx.casa_file.public_id)

      assert {:ok, %{items: [publicado]}} = Ybira.list_files(ctx.reader_scope)
      assert publicado.public_id == ctx.casa_file.public_id
    end

    test "list_folder_contents/3 nao vaza a casa alheia dentro de pasta na praca", ctx do
      {:ok, praca_folder} = Ybira.create_folder(ctx.owner_scope, %{name: "na praca", zona: :praca})
      {:ok, _} = Ybira.move_file(ctx.owner_scope, ctx.casa_file.public_id, praca_folder.public_id)

      assert {:ok, %{folders: [], files: []}} =
               Ybira.list_folder_contents(ctx.reader_scope, praca_folder.public_id)

      {:ok, _} = Ybira.publicar_file(ctx.owner_scope, ctx.casa_file.public_id)

      assert {:ok, %{folders: [], files: [publicado]}} =
               Ybira.list_folder_contents(ctx.reader_scope, praca_folder.public_id)

      assert publicado.public_id == ctx.casa_file.public_id
    end

    test "list_folders/1 esconde a pasta da casa; publicar a pasta libera a pasta, nao os filhos", ctx do
      {:ok, casa_folder} = Ybira.create_folder(ctx.owner_scope, %{name: "da casa"})

      assert {:ok, []} = Ybira.list_folders(ctx.reader_scope)
      assert {:ok, []} = Ybira.list_folders(ctx.zelador_scope)

      {:ok, _} = Ybira.publicar_folder(ctx.owner_scope, casa_folder.public_id)

      assert {:ok, [%{public_id: public_id}]} = Ybira.list_folders(ctx.reader_scope)
      assert public_id == casa_folder.public_id

      {:ok, %{folders: [], files: []}} = Ybira.list_folder_contents(ctx.reader_scope, casa_folder.public_id)
    end

    test "folder_path/2 nao sobe pela casa alheia", ctx do
      {:ok, casa_root} = Ybira.create_folder(ctx.owner_scope, %{name: "raiz da casa"})

      {:ok, praca_leaf} =
        Ybira.create_folder(ctx.owner_scope, %{
          name: "folha na praca",
          parent_public_id: casa_root.public_id,
          zona: :praca
        })

      {:ok, chain} = Ybira.folder_path(ctx.reader_scope, praca_leaf.public_id)
      assert [%{public_id: unico}] = chain
      assert unico == praca_leaf.public_id

      {:ok, _} = Ybira.publicar_folder(ctx.owner_scope, casa_root.public_id)

      {:ok, chain} = Ybira.folder_path(ctx.reader_scope, praca_leaf.public_id)
      assert Enum.map(chain, & &1.public_id) == [casa_root.public_id, praca_leaf.public_id]
    end

    test "list_recent/2 esconde, e a praca libera", ctx do
      assert {:ok, []} = Ybira.list_recent(ctx.reader_scope)

      {:ok, _} = Ybira.publicar_file(ctx.owner_scope, ctx.casa_file.public_id)

      assert {:ok, [recente]} = Ybira.list_recent(ctx.reader_scope)
      assert recente.public_id == ctx.casa_file.public_id
    end

    test "os agregados nao contam a casa alheia", ctx do
      assert {:ok, 0} = Ybira.count_files(ctx.reader_scope)
      assert {:ok, 0} = Ybira.count_photos(ctx.reader_scope)
      assert {:ok, %{photos: 0, videos: 0, documents: 0, others: 0}} = Ybira.storage_stats_by_kind(ctx.reader_scope)

      {:ok, _} = Ybira.publicar_file(ctx.owner_scope, ctx.casa_file.public_id)

      assert {:ok, 1} = Ybira.count_files(ctx.reader_scope)

      assert {:ok, %{photos: 0, videos: 0, documents: bytes, others: 0}} =
               Ybira.storage_stats_by_kind(ctx.reader_scope)

      assert bytes == ctx.casa_file.file_size_bytes
    end

    test "a lixeira so aparece para o dono", ctx do
      {:ok, _} = Ybira.delete_file(ctx.owner_scope, ctx.casa_file.public_id)

      assert {:ok, %{items: []}} = Ybira.list_trash(ctx.reader_scope)
      assert {:ok, %{items: []}} = Ybira.list_trash(ctx.zelador_scope)

      assert {:ok, %{items: [proprio]}} = Ybira.list_trash(ctx.owner_scope)
      assert proprio.public_id == ctx.casa_file.public_id
    end

    test "authorize?/4 nega a outro morador e ao zelador", ctx do
      refute Maraca.authorize?(ctx.reader, :read, "ybira_file", ctx.casa_file.public_id)
      refute Maraca.authorize?(ctx.zelador, :read, "ybira_file", ctx.casa_file.public_id)
      assert Maraca.authorize?(ctx.owner, :read, "ybira_file", ctx.casa_file.public_id)
    end
  end

  describe "jaci: a galeria nao mostra a casa alheia" do
    setup ctx do
      {:ok, foto} = Ybira.upload(ctx.owner_scope, tmp_image_fixture(filename: "festa.jpg"))
      %{foto: foto}
    end

    test "list_photos/2 esconde, e a praca libera", ctx do
      assert {:ok, %{items: []}} = Jaci.list_photos(ctx.reader_scope)
      assert {:ok, %{items: []}} = Jaci.list_photos(ctx.zelador_scope)

      {:ok, _} = Ybira.publicar_file(ctx.owner_scope, ctx.foto.public_id)

      assert {:ok, %{items: [publicada]}} = Jaci.list_photos(ctx.reader_scope)
      assert publicada.public_id == ctx.foto.public_id
    end

    test "timeline/2 esconde, e a praca libera", ctx do
      assert {:ok, %{groups: []}} = Jaci.timeline(ctx.reader_scope)
      assert {:ok, %{groups: []}} = Jaci.timeline(ctx.zelador_scope)

      {:ok, _} = Ybira.publicar_file(ctx.owner_scope, ctx.foto.public_id)

      assert {:ok, %{groups: [_grupo]}} = Jaci.timeline(ctx.reader_scope)
    end
  end

  describe "web: download, thumbnail e telas" do
    test "download recusa o morador B e o zelador; a praca libera", ctx do
      rota = ~p"/files/#{ctx.casa_file.public_id}"
      tela = "/arquivos/#{ctx.casa_file.public_id}"

      conn = build_conn() |> log_in(ctx.reader) |> get(rota)
      assert redirected_to(conn, 302) == tela

      conn = build_conn() |> log_in(ctx.zelador) |> get(rota)
      assert redirected_to(conn, 302) == tela

      {:ok, _} = Ybira.publicar_file(ctx.owner_scope, ctx.casa_file.public_id)

      conn = build_conn() |> log_in(ctx.reader) |> get(rota)
      assert conn.status == 200
      assert response(conn, 200) == @casa_contents
    end

    test "thumbnail recusa o morador B; a praca libera", ctx do
      {:ok, foto} = Ybira.upload(ctx.owner_scope, tmp_image_fixture(filename: "retrato.jpg"))
      rota = ~p"/files/#{foto.public_id}/thumbnail/sm"

      conn = build_conn() |> log_in(ctx.reader) |> get(rota)
      assert redirected_to(conn, 302) == "/arquivos/#{foto.public_id}"

      {:ok, _} = Ybira.publicar_file(ctx.owner_scope, foto.public_id)

      conn = build_conn() |> log_in(ctx.reader) |> get(rota)
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["image/webp"]
    end

    test "a tela de arquivos nao mostra a casa alheia; a praca libera", ctx do
      conn = log_in(build_conn(), ctx.reader)

      {:ok, _lv, html} = live(conn, ~p"/arquivos?zona=casa")
      refute html =~ @casa_filename

      {:ok, _lv, html} = live(conn, ~p"/arquivos?zona=praca")
      refute html =~ @casa_filename

      {:ok, _} = Ybira.publicar_file(ctx.owner_scope, ctx.casa_file.public_id)

      {:ok, _lv, html} = live(conn, ~p"/arquivos?zona=praca")
      assert html =~ @casa_filename
    end

    test "a home nao mostra o recente da casa alheia; a praca libera", ctx do
      conn = log_in(build_conn(), ctx.reader)

      {:ok, _lv, html} = live(conn, ~p"/")
      refute html =~ @casa_filename

      {:ok, _} = Ybira.publicar_file(ctx.owner_scope, ctx.casa_file.public_id)

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ @casa_filename
    end

    test "a galeria nao mostra a foto da casa alheia; a praca libera", ctx do
      {:ok, foto} = Ybira.upload(ctx.owner_scope, tmp_image_fixture(filename: "chacara.jpg"))
      conn = log_in(build_conn(), ctx.reader)

      {:ok, _lv, html} = live(conn, ~p"/fotos")
      refute html =~ foto.public_id

      {:ok, _} = Ybira.publicar_file(ctx.owner_scope, foto.public_id)

      {:ok, _lv, html} = live(conn, ~p"/fotos")
      assert html =~ foto.public_id
    end

    test "a tela do arquivo mostra o pedido de acesso, nunca o conteudo; a praca libera", ctx do
      conn = log_in(build_conn(), ctx.reader)
      rota = ~p"/arquivos/#{ctx.casa_file.public_id}"

      {:ok, _lv, html} = live(conn, rota)
      assert html =~ "Pedir acesso"
      refute html =~ @casa_contents

      {:ok, _} = Ybira.publicar_file(ctx.owner_scope, ctx.casa_file.public_id)

      {:ok, _lv, html} = live(conn, rota)
      refute html =~ "Pedir acesso"
    end

    test "a lixeira na tela so mostra o proprio lixo", ctx do
      {:ok, _} = Ybira.delete_file(ctx.owner_scope, ctx.casa_file.public_id)

      {:ok, _lv, html} = build_conn() |> log_in(ctx.reader) |> live(~p"/arquivos/lixeira")
      refute html =~ @casa_filename

      {:ok, _lv, html} = build_conn() |> log_in(ctx.zelador) |> live(~p"/arquivos/lixeira")
      refute html =~ @casa_filename

      {:ok, _lv, html} = build_conn() |> log_in(ctx.owner) |> live(~p"/arquivos/lixeira")
      assert html =~ @casa_filename
    end

    test "o zelador nao tem atalho nas telas", ctx do
      conn = build_conn() |> log_in(ctx.zelador) |> get(~p"/files/#{ctx.casa_file.public_id}")
      assert redirected_to(conn, 302) == "/arquivos/#{ctx.casa_file.public_id}"

      {:ok, _lv, html} =
        build_conn() |> log_in(ctx.zelador) |> live(~p"/arquivos/#{ctx.casa_file.public_id}")

      assert html =~ "Pedir acesso"
      refute html =~ @casa_contents
    end
  end
end
