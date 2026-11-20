defmodule TainaWeb.UploadLiveTest do
  # Upload admission inspects private staging on the process-wide storage root.
  use TainaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Config
  alias Taina.Repo
  alias Taina.Scope
  alias Taina.Ybira
  alias Taina.Ybira.Upload
  alias Taina.Ybira.Uploads
  alias Taina.Ybira.Workers.Ingest

  @notification_window_ms 650

  setup do
    storage_root = Path.join(System.tmp_dir!(), "taina_upload_live_#{Ecto.UUID.generate()}")
    previous_storage_root = Application.get_env(:taina, :storage_root)
    Application.put_env(:taina, :storage_root, storage_root)

    on_exit(fn ->
      Application.put_env(:taina, :storage_root, previous_storage_root)
      File.rm_rf!(storage_root)
    end)

    tekoa = tekoa_fixture()
    ava = active_ava_fixture(tekoa)
    %{scope: Scope.new(ava, tekoa), ava: ava, tekoa: tekoa}
  end

  # --- boards "Enviar / enviando" e o fluxo concluído ---

  test "envia arquivo e mostra no grupo concluído", %{conn: conn, scope: scope, ava: ava} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar")
    manager = upload_manager(lv)

    input =
      file_input(manager, "#upload-form", :files, [
        %{name: "ata.txt", content: "ata da assembleia", type: "text/plain"}
      ])

    upload = upload_to_queue(manager, input, "ata.txt", scope)
    assert {:ok, %{items: []}} = Ybira.list_files(scope)
    assert :ok = perform_ingest(upload)
    render(manager)

    html = render(lv)
    assert html =~ "Concluído"
    assert html =~ "ata.txt"

    assert {:ok, %{items: [file]}} = Ybira.list_files(scope)
    assert file.nome == "ata.txt"
  end

  test "a seleção publica os limites da fila combinada", %{conn: conn, ava: ava} do
    {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/documentos/enviar")
    manager = upload_manager(lv)

    assert html =~ ~S(phx-hook="UploadQueueHook")
    assert html =~ ~s(data-upload-queue-max-concurrent="#{Config.max_concurrent_uploads()}")
    assert has_element?(manager, "#upload-form[data-upload-queue-active-ids='']")
    assert has_element?(manager, "#dropzone[phx-drop-target][phx-hook='DragClass']")
    assert has_element?(manager, "#dropzone input[name='files'][data-upload-queue-input='files']")
    assert has_element?(manager, "input[name='files'][data-upload-queue-input='files']")
    assert has_element?(manager, "input[name='folders'][data-upload-queue-input='folders']")
    assert has_element?(manager, "input[name='camera'][data-upload-queue-input='camera']")
    refute html =~ "UploadSelectionLimit"
  end

  test "oferece a escolha de pastas no desktop", %{conn: conn, ava: ava} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar")
    manager = upload_manager(lv)

    assert has_element?(manager, "#folder-input input[name='folders'][webkitdirectory]")
  end

  test "o voltar aponta a pasta de destino, pelo nome", %{conn: conn, scope: scope, ava: ava} do
    {:ok, folder} = Ybira.create_folder(scope, %{name: "Atas"})

    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar?#{[pasta: folder.rkey]}")

    assert has_element?(lv, ".page-header__title", "Documentos")
    assert has_element?(lv, ".page-header__back-label", "Atas")
    assert has_element?(lv, ~s(.page-header__back[href="/documentos/pasta/#{folder.rkey}"]))
  end

  test "return_to interno mantém a origem de Grade e Linha do tempo", %{conn: conn, ava: ava} do
    for origin <- ["/galeria?zona=casa", "/galeria/linha-do-tempo?zona=praca"] do
      path = "/documentos/enviar?return_to=" <> URI.encode_www_form(origin)
      {:ok, lv, _html} = conn |> log_in(ava) |> live(path)

      assert has_element?(lv, ~s(.page-header__back[href="#{origin}"]))
    end
  end

  test "return_to externo usa o fallback Casa", %{conn: conn, ava: ava} do
    path = "/documentos/enviar?return_to=" <> URI.encode_www_form("https://example.com/fora")
    {:ok, lv, _html} = conn |> log_in(ava) |> live(path)

    assert has_element?(lv, ~S(.page-header__back[href="/documentos"]))
    refute render(lv) =~ "example.com"
  end

  test "envia para a pasta indicada em ?pasta=", %{conn: conn, scope: scope, ava: ava} do
    {:ok, folder} = Ybira.create_folder(scope, %{name: "Atas"})
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar?#{[pasta: folder.rkey]}")
    manager = upload_manager(lv)

    input =
      file_input(manager, "#upload-form", :files, [
        %{name: "junho.txt", content: "ata de junho", type: "text/plain"}
      ])

    upload = upload_to_queue(manager, input, "junho.txt", scope)
    assert upload.folder_rkey == folder.rkey
    assert :ok = perform_ingest(upload)
    render(manager)

    assert {:ok, %{files: [file]}} = Ybira.list_folder_contents(scope, folder.rkey)
    assert file.nome == "junho.txt"
  end

  test "envia pasta preservando a hierarquia e reutilizando pastas do mesmo caminho", %{
    conn: conn,
    scope: scope,
    ava: ava
  } do
    {:ok, destination} = Ybira.create_folder(scope, %{name: "Destino"})
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar?#{[pasta: destination.rkey]}")
    manager = upload_manager(lv)

    input =
      file_input(manager, "#upload-form", :folders, [
        %{name: "junho.txt", relative_path: "Atas/2026/junho.txt", content: "ata de junho", type: "text/plain"},
        %{name: "julho.txt", relative_path: "Atas/2026/julho.txt", content: "ata de julho", type: "text/plain"},
        %{name: "capa.txt", relative_path: "Atas/capa.txt", content: "capa", type: "text/plain"}
      ])

    uploads =
      Enum.map(["junho.txt", "julho.txt", "capa.txt"], fn name ->
        upload_to_queue(manager, input, name, scope)
      end)

    assert Enum.all?(uploads, &(&1.state == :queued))
    Enum.each(uploads, &perform_ingest/1)
    render(manager)

    assert {:ok, %{folders: [atas], files: []}} = Ybira.list_folder_contents(scope, destination.rkey)
    assert atas.nome == "Atas"

    assert {:ok, %{folders: [ano], files: [capa]}} = Ybira.list_folder_contents(scope, atas.rkey)
    assert ano.nome == "2026"
    assert capa.nome == "capa.txt"

    assert {:ok, %{folders: [], files: files}} = Ybira.list_folder_contents(scope, ano.rkey)
    assert files |> Enum.map(& &1.nome) |> Enum.sort() == ["julho.txt", "junho.txt"]
  end

  test "arquivo rejeitado pelo worker aparece como falha", %{conn: conn, scope: scope, ava: ava} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar")
    manager = upload_manager(lv)

    # ELF magic bytes, executável, rejeitado pela allowlist de MIME
    input =
      file_input(manager, "#upload-form", :files, [
        %{name: "virus.bin", content: <<0x7F, ?E, ?L, ?F, 0, 1, 2, 3>>, type: "application/octet-stream"}
      ])

    upload = upload_to_queue(manager, input, "virus.bin", scope)
    assert {:cancel, :invalid_mime} = perform_ingest(upload)
    render(manager)

    html = render(manager)
    assert html =~ "Falharam"
    assert html =~ "Não aceitamos este tipo de arquivo. Use imagens, PDFs, texto, áudio, vídeo ou ZIP."

    # rejeição vale no domínio, não só na UI: nada foi persistido
    assert {:ok, %{items: []}} = Ybira.list_files(scope)
  end

  test "entrada da câmera chega a CONCLUÍDO", %{conn: conn, scope: scope, ava: ava} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar")
    manager = upload_manager(lv)

    # JPEG de verdade: o Ybira detecta MIME pelos magic bytes, não pela extensão
    content = File.read!(tmp_image_fixture(width: 8, height: 8))

    input =
      file_input(manager, "#upload-form", :camera, [
        %{name: "foto-da-roca.jpg", content: content, type: "image/jpeg"}
      ])

    upload = upload_to_queue(manager, input, "foto-da-roca.jpg", scope)
    assert :ok = perform_ingest(upload)
    render(manager)

    html = render(lv)
    assert html =~ "Concluído"
    assert html =~ "foto-da-roca.jpg"

    assert {:ok, %{items: [file]}} = Ybira.list_files(scope)
    assert file.nome == "foto-da-roca.jpg"
  end

  test "a linha concluída mostra sucesso sem ação de publicar", %{
    conn: conn,
    scope: scope,
    ava: ava
  } do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar")
    manager = upload_manager(lv)

    input =
      file_input(manager, "#upload-form", :files, [
        %{name: "ata.txt", content: "ata da assembleia", type: "text/plain"}
      ])

    upload = upload_to_queue(manager, input, "ata.txt", scope)
    refute render(manager) =~ "Concluído"
    assert :ok = perform_ingest(upload)
    render(manager)

    html = render(lv)
    assert has_element?(lv, ".list-row .text-success")
    refute html =~ "Publicar na praça"
    refute html =~ "Na praça"
    refute html =~ "Você pode continuar usando o app enquanto envia."

    assert {:ok, %{items: [file]}} = Ybira.list_files(scope)
    assert file.zona == :casa
  end

  test "erro de cota: a caixa explica com a cópia do board e aponta o espaço", %{
    conn: conn,
    scope: scope,
    ava: ava,
    tekoa: tekoa
  } do
    # cota de 10 bytes já consumida: qualquer envio estoura
    tekoa |> Ecto.Changeset.change(storage_quota_bytes: 10, storage_used_bytes: 10) |> Repo.update!()

    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar")
    manager = upload_manager(lv)

    input =
      file_input(manager, "#upload-form", :files, [
        %{name: "grande.txt", content: "esse conteúdo passa da cota", type: "text/plain"}
      ])

    render_upload(input, "grande.txt")
    render(manager)

    html = render(lv)
    assert has_element?(lv, ".dropzone--error-cota")
    assert html =~ "O espaço da comunidade acabou. Peça a quem cuida da nuvem para liberar."
    assert has_element?(lv, ~S(a[href="/armazenamento"]), "Ver espaço")
    # nada persistiu: a cota vale no domínio
    assert {:ok, %{items: []}} = Ybira.list_files(scope)
  end

  test "o manager único fica oculto fora de Enviar", %{conn: conn, ava: ava} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/")
    manager = upload_manager(lv)

    assert manager.module == TainaWeb.UploadManagerLive
    assert has_element?(lv, "#upload-manager[hidden][inert][aria-hidden='true']")
    assert has_element?(manager, "#upload-manager-panel")
  end

  test "the sticky manager applies route visibility updates without remounting", %{
    conn: conn,
    ava: ava
  } do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/")
    manager = upload_manager(lv)

    send(manager.pid, {:upload_manager_visibility, true})
    assert_push_event(manager, "upload_manager_visibility", %{visible: true})

    send(manager.pid, {:upload_manager_visibility, false})
    assert_push_event(manager, "upload_manager_visibility", %{visible: false})

    assert manager.pid == upload_manager(lv).pid
  end

  test "a terminal notification uses persisted state and names one successful file", %{
    conn: conn,
    scope: scope,
    ava: ava
  } do
    upload = complete_upload(scope, "atas.txt", "reunião de moradores")
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/")

    send(lv.pid, {:ybira_upload, upload.public_id, :processing})
    render(lv)
    refute has_element?(lv, "#flash-info")
    refute has_element?(lv, "#flash-error")

    send(lv.pid, {:ybira_upload, upload.public_id, :failed})
    send(lv.pid, {:ybira_upload, upload.public_id, :completed})
    await_notification_window()
    render(lv)

    assert has_element?(lv, "#flash-info", "atas.txt foi enviado.")
    refute has_element?(lv, "#flash-error")
  end

  test "terminal batches aggregate mixed outcomes and deduplicate each upload state", %{
    conn: conn,
    scope: scope,
    ava: ava
  } do
    completed = complete_upload(scope, "foto.txt", "foto da comunidade")
    failed = fail_upload(scope, "arquivo.bin", <<0x4D, 0x5A, 0x90, 0x00, "invalid">>)
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/")

    send(lv.pid, {:ybira_upload, completed.public_id, :completed})
    send(lv.pid, {:ybira_upload, failed.public_id, :failed})
    send(lv.pid, {:ybira_upload, completed.public_id, :completed})
    send(lv.pid, {:ybira_upload, failed.public_id, :failed})
    await_notification_window()
    render(lv)

    assert has_element?(lv, "#flash-error", "1 arquivo enviado")
    assert has_element?(lv, "#flash-error", "1 envio falhou")
    refute has_element?(lv, "#flash-info")
    refute has_element?(lv, "#flash-error", "2 arquivos enviados")
  end

  test "the Enviar screen leaves terminal upload results to its sticky manager", %{
    conn: conn,
    scope: scope,
    ava: ava
  } do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar")
    manager = upload_manager(lv)
    upload = complete_upload(scope, "memoria.txt", "memória da comunidade")

    send(lv.pid, {:ybira_upload, upload.public_id, :completed})
    render(lv)
    render(manager)

    refute has_element?(lv, "#flash-info")
    refute has_element?(lv, "#flash-error")
    assert has_element?(manager, ".list-row .text-success")
    assert has_element?(manager, ".list-row", "memoria.txt")
  end

  test "pending queue entries stay visible without transfer progress and can be cancelled", %{
    conn: conn,
    ava: ava
  } do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar")
    manager = upload_manager(lv)

    render_hook(manager, "upload_queue_pending", %{
      revision: 1,
      items: [
        %{
          queue_id: "pending-one",
          input_key: "files",
          name: "same.txt",
          size: 12,
          destination_folder: nil,
          relative_path: "same.txt"
        },
        %{
          queue_id: "pending-two",
          input_key: "camera",
          name: "same.txt",
          size: 20,
          destination_folder: nil,
          relative_path: "same.txt"
        }
      ]
    })

    html = render(manager)
    assert has_element?(manager, "#pending-upload-pending-one", "Aguardando para enviar")
    assert has_element?(manager, "#pending-upload-pending-two", "Aguardando para enviar")
    refute html =~ "0%"

    render_click(manager, "cancel_pending_upload", %{"queue_id" => "pending-one"})
    assert_push_event(manager, "upload_queue_cancel", %{queue_id: "pending-one"})

    refute has_element?(manager, "#pending-upload-pending-one")
    assert has_element?(manager, "#pending-upload-pending-two")
  end

  test "cancelling an active entry uses its ref and releases the queue reservation", %{
    conn: conn,
    scope: scope,
    ava: ava
  } do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar")
    manager = upload_manager(lv)

    render_hook(manager, "upload_queue_item", %{
      queue_id: "active-cancel",
      input_key: "files",
      destination_folder: nil,
      relative_path: "active.txt",
      client_name: "not-the-entry-name.txt",
      client_size: 1
    })

    input =
      file_input(manager, "#upload-form", :files, [
        %{name: "active.txt", content: "active bytes", type: "text/plain"}
      ])

    render_upload(input, "active.txt", 0)
    assert has_element?(manager, "#upload-form[data-upload-queue-active-ids='active-cancel']")
    assert has_element?(manager, "button[phx-click='cancel_active_upload']", "Cancelar")

    assert [%{"ref" => entry_ref}] = input.entries
    render_click(manager, "cancel_active_upload", %{"entry_ref" => entry_ref})

    assert_push_event(manager, "upload_queue_cancel", %{queue_id: "active-cancel"})
    assert has_element?(manager, "#upload-form[data-upload-queue-active-ids='']")
    assert {:ok, []} = Uploads.list(scope)
  end

  test "a entrada mantém a pasta de destino capturada ao mudar o contexto da rota", %{
    conn: conn,
    scope: scope,
    ava: ava
  } do
    {:ok, first_folder} = Ybira.create_folder(scope, %{name: "Primeira"})
    {:ok, second_folder} = Ybira.create_folder(scope, %{name: "Segunda"})

    {:ok, lv, _html} =
      conn
      |> log_in(ava)
      |> live(~p"/documentos/enviar?#{[pasta: first_folder.rkey]}")

    manager = upload_manager(lv)

    input =
      file_input(manager, "#upload-form", :files, [
        %{name: "ata.txt", content: "ata da primeira pasta", type: "text/plain"}
      ])

    render_upload(input, "ata.txt", 0)
    render_patch(lv, ~p"/documentos/enviar?#{[pasta: second_folder.rkey]}")
    assert manager.pid == upload_manager(lv).pid

    render_upload(input, "ata.txt")
    render(manager)

    assert {:ok, [upload]} = Uploads.list(scope)
    assert upload.folder_rkey == first_folder.rkey
    assert upload.state == :queued
    assert {:ok, %{files: []}} = Ybira.list_folder_contents(scope, second_folder.rkey)

    assert :ok = perform_ingest(upload)
    render(manager)

    assert {:ok, %{files: [file]}} = Ybira.list_folder_contents(scope, first_folder.rkey)
    assert file.nome == "ata.txt"
  end

  test "queue metadata uses input FIFO identity and releases its reservation at handoff", %{
    conn: conn,
    scope: scope,
    ava: ava
  } do
    {:ok, metadata_folder} = Ybira.create_folder(scope, %{name: "Metadata"})
    {:ok, second_metadata_folder} = Ybira.create_folder(scope, %{name: "Segunda metadata"})

    {:ok, lv, _html} =
      conn
      |> log_in(ava)
      |> live(~p"/documentos/enviar")

    manager = upload_manager(lv)

    render_hook(manager, "upload_queue_item", %{
      queue_id: "queue-item-1",
      input_key: "files",
      destination_folder: metadata_folder.rkey,
      relative_path: "Atas/2026/primeiro.txt",
      client_name: "not-the-first-entry-name.txt",
      client_size: 1
    })

    render_hook(manager, "upload_queue_item", %{
      queue_id: "queue-item-2",
      input_key: "files",
      destination_folder: second_metadata_folder.rkey,
      relative_path: "Relatorios/2026/segundo.txt",
      client_name: "not-the-second-entry-name.txt",
      client_size: 1
    })

    assert has_element?(manager, "#upload-form[data-upload-queue-active-ids='queue-item-1 queue-item-2']")

    input =
      file_input(manager, "#upload-form", :files, [
        %{name: "primeiro.txt", content: "primeiro registro", type: "text/plain"},
        %{name: "segundo.txt", content: "segundo registro", type: "text/plain"}
      ])

    render_upload(input, "primeiro.txt", 0)
    render_upload(input, "segundo.txt", 0)
    render_upload(input, "primeiro.txt")
    render_upload(input, "segundo.txt")
    render(manager)

    assert has_element?(manager, "#upload-form[data-upload-queue-active-ids='']")
    assert {:ok, [%Upload{}, %Upload{}]} = Uploads.list(scope)
    {:ok, uploads} = Uploads.list(scope)
    assert Enum.all?(uploads, &(&1.state == :queued))

    first = Enum.find(uploads, &(&1.filename == "primeiro.txt"))
    second = Enum.find(uploads, &(&1.filename == "segundo.txt"))

    assert first.size == byte_size("primeiro registro")
    assert first.folder_rkey == metadata_folder.rkey
    assert first.relative_path == "Atas/2026/primeiro.txt"
    assert second.size == byte_size("segundo registro")
    assert second.folder_rkey == second_metadata_folder.rkey
    assert second.relative_path == "Relatorios/2026/segundo.txt"
    assert {:ok, %{files: [], folders: []}} = Ybira.list_folder_contents(scope, metadata_folder.rkey)
    assert {:ok, %{files: [], folders: []}} = Ybira.list_folder_contents(scope, second_metadata_folder.rkey)
    assert {:ok, %{items: []}} = Ybira.list_files(scope)
  end

  test "queued metadata keeps its folder hierarchy through worker completion", %{
    conn: conn,
    scope: scope,
    ava: ava
  } do
    {:ok, route_folder} = Ybira.create_folder(scope, %{name: "Rota"})
    {:ok, metadata_folder} = Ybira.create_folder(scope, %{name: "Metadata"})
    {:ok, later_folder} = Ybira.create_folder(scope, %{name: "Depois"})

    {:ok, lv, _html} =
      conn
      |> log_in(ava)
      |> live(~p"/documentos/enviar?#{[pasta: route_folder.rkey]}")

    manager = upload_manager(lv)

    render_hook(manager, "upload_queue_item", %{
      queue_id: "queue-hierarchy",
      input_key: "files",
      destination_folder: metadata_folder.rkey,
      relative_path: "Atas/2026/registro.txt",
      client_name: "metadata-name.txt",
      client_size: 1
    })

    input =
      file_input(manager, "#upload-form", :files, [
        %{name: "registro.txt", content: "registro da comunidade", type: "text/plain"}
      ])

    render_upload(input, "registro.txt", 0)
    render_patch(lv, ~p"/documentos/enviar?#{[pasta: later_folder.rkey]}")
    render_upload(input, "registro.txt")
    render(manager)

    assert {:ok, [upload]} = Uploads.list(scope)
    assert upload.state == :queued
    assert upload.folder_rkey == metadata_folder.rkey
    assert upload.relative_path == "Atas/2026/registro.txt"
    assert {:ok, %{files: [], folders: []}} = Ybira.list_folder_contents(scope, metadata_folder.rkey)

    assert :ok = perform_ingest(upload)
    render(manager)

    assert has_element?(manager, ".list-row .text-success")
    assert has_element?(manager, ".list-row", "registro.txt")

    assert {:ok, %{files: [], folders: [atas]}} =
             Ybira.list_folder_contents(scope, metadata_folder.rkey)

    assert atas.nome == "Atas"
    assert {:ok, %{files: [], folders: [ano]}} = Ybira.list_folder_contents(scope, atas.rkey)
    assert ano.nome == "2026"
    assert {:ok, %{files: [file], folders: []}} = Ybira.list_folder_contents(scope, ano.rkey)
    assert file.nome == "registro.txt"
  end

  defp upload_manager(lv) do
    assert manager = find_live_child(lv, "upload-manager")
    manager
  end

  defp upload_to_queue(manager, input, filename, scope) do
    render_upload(input, filename)
    render(manager)

    assert {:ok, uploads} = Uploads.list(scope)
    assert %Upload{} = upload = Enum.find(uploads, &(&1.filename == filename))
    assert upload.state == :queued
    assert has_element?(manager, ".list-row__meta", "Na fila")
    upload
  end

  defp perform_ingest(upload) do
    Ingest.perform(%Oban.Job{
      id: upload.oban_job_id,
      args: %{"upload_id" => upload.public_id},
      attempt: 1,
      max_attempts: 3
    })
  end

  defp complete_upload(scope, filename, contents) do
    upload = stage_upload(scope, filename, contents)
    assert :ok = perform_ingest(upload)
    durable_upload(scope, upload.public_id)
  end

  defp fail_upload(scope, filename, contents) do
    upload = stage_upload(scope, filename, contents)
    assert {:cancel, :invalid_mime} = perform_ingest(upload)
    durable_upload(scope, upload.public_id)
  end

  defp stage_upload(scope, filename, contents) do
    path = tmp_upload_fixture(contents, filename)

    assert {:ok, upload} =
             Uploads.stage_and_enqueue(scope, path, %{
               filename: filename,
               size: byte_size(contents)
             })

    upload
  end

  defp durable_upload(scope, public_id) do
    assert {:ok, uploads} = Uploads.list(scope)
    assert %Upload{} = upload = Enum.find(uploads, &(&1.public_id == public_id))
    upload
  end

  defp await_notification_window do
    reference = make_ref()
    Process.send_after(self(), {:notification_window_elapsed, reference}, @notification_window_ms + 50)
    assert_receive {:notification_window_elapsed, ^reference}, 1_000
  end
end
