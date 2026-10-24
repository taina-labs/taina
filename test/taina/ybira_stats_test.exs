defmodule Taina.YbiraStatsTest do
  use Taina.DataCase, async: true

  import Taina.Fixtures

  alias Taina.Scope
  alias Taina.Ybira

  setup do
    %{scope: scope_fixture()}
  end

  describe "list_recent/2" do
    test "devolve os últimos envios, mais novos primeiro, fora da lixeira", %{scope: scope} do
      {:ok, old} = Ybira.upload(scope, tmp_upload_fixture("um", "a.txt"))
      {:ok, deleted} = Ybira.upload(scope, tmp_upload_fixture("dois", "b.txt"))
      {:ok, newest} = Ybira.upload(scope, tmp_upload_fixture("três", "c.txt"))
      {:ok, _} = Ybira.delete_file(scope, deleted.rkey)

      assert {:ok, [first, second]} = Ybira.list_recent(scope, limit: 2)
      assert first.id == newest.id
      assert second.id == old.id
    end
  end

  describe "count_files/1 e count_photos/1" do
    test "contam ativos; fotos só image/*, vídeo não conta como foto", %{scope: scope} do
      {:ok, _doc} = Ybira.upload(scope, tmp_upload_fixture())
      {:ok, _img} = Ybira.upload(scope, tmp_image_fixture())
      {:ok, _vid} = Ybira.upload(scope, tmp_video_fixture())
      {:ok, trashed} = Ybira.upload(scope, tmp_upload_fixture("x", "x.txt"))
      {:ok, _} = Ybira.delete_file(scope, trashed.rkey)

      assert {:ok, 3} = Ybira.count_files(scope)
      assert {:ok, 1} = Ybira.count_photos(scope)
    end
  end

  describe "storage_stats_by_kind/1" do
    test "agrupa bytes por categoria de mídia", %{scope: scope} do
      {:ok, doc} = Ybira.upload(scope, tmp_upload_fixture("documento", "doc.txt"))
      {:ok, img} = Ybira.upload(scope, tmp_image_fixture())

      assert {:ok, by_kind} = Ybira.storage_stats_by_kind(scope)
      assert by_kind.photos == img.tamanho
      assert by_kind.documents == doc.tamanho
      assert by_kind.videos == 0
      assert by_kind.others == 0
    end

    test "tudo zerado sem arquivos", %{scope: scope} do
      assert {:ok, %{photos: 0, videos: 0, documents: 0, others: 0}} = Ybira.storage_stats_by_kind(scope)
    end
  end

  # Fato da máquina (uso/cota) é comunitário; o detalhe por zona é o mesmo
  # fato, tekoa inteiro: a casa de outra pessoa ocupa bytes mesmo sem quem
  # quer que possa lê-la (RFC_003 D2 é a regra de leitura, não a de ocupação).
  describe "storage_stats_by_zone/1" do
    test "separa casa, praça e lixeira; a soma bate com o uso da Tekoa", %{scope: scope} do
      {:ok, _em_casa} = Ybira.upload(scope, tmp_upload_fixture("conteudo casa", "casa.txt"))
      {:ok, na_praca} = Ybira.upload(scope, tmp_upload_fixture("conteudo praca", "praca.txt"))
      {:ok, _} = Ybira.publicar_file(scope, na_praca.rkey)

      {:ok, %{used_bytes: used}} = Ybira.storage_stats(scope)
      assert {:ok, zona} = Ybira.storage_stats_by_zone(scope)

      assert zona == %{
               casa: byte_size("conteudo casa"),
               praca: byte_size("conteudo praca"),
               lixeira: 0
             }

      assert zona.casa + zona.praca + zona.lixeira == used
    end

    test "apagar conta na lixeira (os bytes ficam até o expurgo)", %{scope: scope} do
      {:ok, _vivo} = Ybira.upload(scope, tmp_upload_fixture("conteudo vivo", "vivo.txt"))
      {:ok, apagado} = Ybira.upload(scope, tmp_upload_fixture("conteudo morto", "morto.txt"))
      {:ok, _} = Ybira.delete_file(scope, apagado.rkey)

      assert {:ok, zona} = Ybira.storage_stats_by_zone(scope)
      assert zona.lixeira == byte_size("conteudo morto")
      assert zona.casa == byte_size("conteudo vivo")
      assert zona.praca == 0

      {:ok, %{used_bytes: used}} = Ybira.storage_stats(scope)
      assert zona.casa + zona.praca + zona.lixeira == used
    end

    test "a casa de outro morador conta em bytes mesmo sem leitura", %{scope: scope} do
      outra = active_ava_fixture(scope.tekoa)
      outra_scope = Scope.new(outra, scope.tekoa)
      {:ok, img} = Ybira.upload(outra_scope, tmp_image_fixture(filename: "casa.jpg"))

      assert {:ok, zona} = Ybira.storage_stats_by_zone(scope)
      assert zona.casa == img.tamanho
      assert {:ok, %{used_bytes: used}} = Ybira.storage_stats(scope)
      assert zona.casa + zona.praca + zona.lixeira == used
    end

    test "tudo zerado sem arquivos", %{scope: scope} do
      assert {:ok, %{casa: 0, praca: 0, lixeira: 0}} = Ybira.storage_stats_by_zone(scope)
    end
  end

  # Fato da máquina (uso/cota) é comunitário; o detalhe por tipo segue a regra
  # de leitura das duas zonas (RFC_003 D2): a casa de outra pessoa não conta
  # para quem não pode ler, até a publicação na praça.
  describe "agregados legíveis (RFC_003 D2)" do
    test "arquivo na casa de outro morador só entra quando publicado na praça", %{scope: scope} do
      outra = active_ava_fixture(scope.tekoa)
      outra_scope = Scope.new(outra, scope.tekoa)
      {:ok, img} = Ybira.upload(outra_scope, tmp_image_fixture(filename: "casa.jpg"))

      # Uso e cota seguem o fato da máquina: comunitários.
      assert {:ok, %{used_bytes: used}} = Ybira.storage_stats(scope)
      assert used == img.tamanho

      assert {:ok, 0} = Ybira.count_files(scope)
      assert {:ok, 0} = Ybira.count_photos(scope)
      assert {:ok, %{photos: 0, videos: 0, documents: 0, others: 0}} = Ybira.storage_stats_by_kind(scope)

      {:ok, _} = Ybira.publicar_file(outra_scope, img.rkey)

      assert {:ok, 1} = Ybira.count_files(scope)
      assert {:ok, 1} = Ybira.count_photos(scope)

      assert {:ok, %{photos: photos, videos: 0, documents: 0, others: 0}} = Ybira.storage_stats_by_kind(scope)
      assert photos == img.tamanho
    end
  end
end
