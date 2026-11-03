defmodule TainaWeb.UploadLive do
  @moduledoc """
  Envio de arquivos (boards "Servico / Ybira Enviar / enviando"
  cc1037dc-e8ab-80cc-8008-d5e2162dfb73 e "erro cota" ...d5e218361ef0): tela
  empurrada do Documentos, sem abas. O voltar aponta a pasta de destino
  ("< Atas"); a caixa de envio mostra os estados do board: parada, enviando
  (progresso do arquivo corrente) e erro de espaço, com a saída "Ver espaço".

  LiveView uploads com `auto_upload`; cada arquivo concluído vai direto para
  `Ybira.upload/3` (validação por magic bytes e cota acontecem lá) e nasce na
  casa. A câmera do celular é uma segunda entrada (RFC 002, fase 3) para o mesmo
  destino, para não tirar da pessoa a escolha de arquivos existentes.

  `?pasta=<rkey>` define a pasta de destino.
  """

  use TainaWeb, :live_view

  alias Taina.Ybira
  alias TainaWeb.InternalPath
  alias TainaWeb.Layouts

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope
    {folder, folder_note} = resolve_folder(scope, params["pasta"])
    max_blob_size = Ybira.max_blob_size()

    socket =
      socket
      |> assign(:page_title, gettext("Documentos"))
      |> assign(:folder, folder)
      |> assign(:return_to, InternalPath.return_to(params["return_to"], back_path(folder)))
      |> assign(:quota_error?, false)
      |> assign(:max_blob_size, max_blob_size)
      |> assign(:done, [])
      |> assign(:failed, [])
      |> maybe_flash_folder_note(folder_note)
      |> allow_upload(:files,
        accept: :any,
        max_entries: 10,
        max_file_size: max_blob_size,
        auto_upload: true,
        progress: &handle_progress/3
      )
      |> allow_upload(:camera,
        accept: :any,
        max_entries: 10,
        max_file_size: max_blob_size,
        auto_upload: true,
        progress: &handle_progress/3
      )

    {:ok, socket}
  end

  # Pasta inexistente ou casa de outra pessoa: sobe para a raiz sem travar o
  # envio; o flash explica por que a pasta sumiu do voltar.
  defp resolve_folder(_scope, nil), do: {nil, nil}

  defp resolve_folder(scope, rkey) do
    case Ybira.get_folder(scope, rkey) do
      {:ok, folder} ->
        {folder, nil}

      {:error, _reason} ->
        {nil, gettext("A pasta original não está mais disponível. O envio vai para o início.")}
    end
  end

  defp maybe_flash_folder_note(socket, nil), do: socket
  defp maybe_flash_folder_note(socket, note), do: put_flash(socket, :error, note)

  # Consome cada arquivo assim que termina de subir, de qualquer um dos dois
  # envios (arquivos ou câmera); o resultado vai para a lista concluído (ou
  # para os erros, sem derrubar os demais envios).
  defp handle_progress(_name, entry, socket) do
    if entry.done?, do: finish_upload(entry, socket), else: {:noreply, socket}
  end

  defp finish_upload(entry, socket) do
    scope = socket.assigns.current_scope

    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok, Ybira.upload(scope, path, upload_opts(entry, socket.assigns.folder))}
      end)

    case result do
      {:ok, file} ->
        {:noreply, update(socket, :done, &[file | &1])}

      {:error, :storage_quota_exceeded} ->
        # Board "erro cota": a caixa explica o espaço e aponta a saída ("Ver
        # espaço"); sem repetir a falha em lista.
        {:noreply, assign(socket, :quota_error?, true)}

      {:error, reason} ->
        {:noreply, update(socket, :failed, &[{entry.client_name, upload_error(reason)} | &1])}
    end
  end

  defp upload_opts(entry, nil), do: [filename: entry.client_name]
  defp upload_opts(entry, folder), do: [filename: entry.client_name, folder_rkey: folder.rkey]

  # Cada erro explica o que houve e dá a saída (tom-de-voz: erros com saída,
  # sem culpa). A cópia de cota é da caixa (Dropzone, board), não da lista.
  defp upload_error(:mime_not_allowed),
    do: gettext("Não aceitamos este tipo de arquivo. Use imagens, PDFs, texto, áudio, vídeo ou ZIP.")

  defp upload_error(_reason), do: gettext("O envio falhou. Toque na caixa acima para tentar de novo.")

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  # O shell inscreve o morador nos eventos do Ava; esta tela não reage a eles,
  # mas precisa ignorar o que não trata.
  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # --- core puro: dados -> dados ---

  # A palavra do voltar: o nome da pasta de destino quando há uma, senão o
  # padrão da casca (spec 1.5, limite de 12 caracteres em back_label/1).
  defp folder_back_label(nil), do: nil
  defp folder_back_label(folder), do: back_label(folder.nome)

  defp return_label(return_to, folder) do
    return_to
    |> URI.parse()
    |> Map.fetch!(:path)
    |> return_label_from_path(folder)
    |> back_label()
  end

  defp return_label_from_path(path, _folder) when path in ["/galeria", "/galeria/linha-do-tempo"], do: gettext("Galeria")

  defp return_label_from_path("/documentos/praca", _folder), do: gettext("Praça")
  defp return_label_from_path("/documentos/lixeira", _folder), do: gettext("Lixeira")

  defp return_label_from_path("/documentos/pasta/" <> _folder_id, folder),
    do: folder_back_label(folder) || gettext("Documentos")

  defp return_label_from_path("/moradores", _folder), do: gettext("Moradores")
  defp return_label_from_path("/conta", _folder), do: gettext("Conta")
  defp return_label_from_path(_path, folder), do: folder_back_label(folder) || gettext("Casa")

  # Onde os arquivos caíram: na pasta alvo, ou no início já na casa (o
  # destino de quem chega pela raiz). Cair na praça faria o recém-chegado
  # "sumir" da tela.
  defp back_path(nil), do: ~p"/documentos"
  defp back_path(folder), do: ~p"/documentos/pasta/#{folder.rkey}"

  # State da caixa (board): estourou a cota, o painel explica e aponta o
  # espaço; com envio em voo, o progresso do arquivo corrente; senão, parada.
  defp dropzone_state(_uploads, true), do: "error-cota"

  defp dropzone_state(uploads, _quota_error) do
    if uploads.files.entries == [], do: "idle", else: "uploading"
  end

  # Erros de configuração (tamanho, quantidade) somados dos dois envios.
  defp config_errors(uploads), do: upload_errors(uploads.files) ++ upload_errors(uploads.camera)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.page
      flash={@flash}
      title={gettext("Documentos")}
      back={@return_to}
      back_label={return_label(@return_to, @folder)}
    >
      <div class="col gap-6 mx-auto w-full measure-md">
        <form
          id="upload-form"
          phx-change="validate"
          phx-submit="validate"
          phx-hook="UploadSelectionLimit"
          data-upload-max-entries="10"
        >
          <.dropzone
            id="dropzone"
            upload={@uploads.files}
            state={dropzone_state(@uploads, @quota_error?)}
            error_href={~p"/armazenamento"}
            class="w-full"
          />

          <label id="camera-input" class="dropzone hide-desktop mt-3" :if={!@quota_error?}>
            <.icon name="image" size={28} />
            <span class="type-label text-primary">{gettext("Tirar foto com a câmera")}</span>
            <span class="type-caption text-muted">
              {gettext("A foto começa na sua casa. Publique na praça para todos verem.")}
            </span>
            <.live_file_input upload={@uploads.camera} capture="environment" class="sr-only" />
          </label>

           <p :for={err <- config_errors(@uploads)} class="field__error mt-2">
             {upload_config_error(err, @max_blob_size)}
          </p>
        </form>

        <div :if={@failed != []}>
          <p class="type-overline text-error mb-2">{gettext("Falharam (%{count})", count: length(@failed))}</p>
          <ul class="list">
            <.list_row :for={{name, reason} <- @failed} kind="file" title={name} meta={reason} meta_class="text-error">
              <:leading>
                <.service_square mark="neutral" />
              </:leading>
            </.list_row>
          </ul>
        </div>

        <div :if={@done != []}>
          <p class="type-overline text-muted mb-2">{gettext("Concluído (%{count})", count: length(@done))}</p>
          <ul class="list">
            <.list_row
              :for={file <- @done}
              kind="file"
              title={file.nome}
              meta={gettext("Concluído")}
              meta_class="text-success"
            >
              <:leading>
                <.service_square mark={file_mark(file.mime)} />
              </:leading>
              <:actions>
                <.icon name="check" size={20} class="text-success" />
              </:actions>
            </.list_row>
          </ul>
        </div>
      </div>
    </Layouts.page>
    """
  end

  # O quadradinho da linha concluída: o mesmo mapa do hub e do navegador.
  defp upload_config_error(:too_large, max_blob_size),
    do: gettext("O arquivo passa de %{size}, o limite por arquivo.", size: format_bytes(max_blob_size))

  defp upload_config_error(:too_many_files, _max_blob_size),
    do: gettext("São no máximo 10 arquivos por vez. Envie o resto em seguida.")

  defp upload_config_error(_err, _max_blob_size), do: gettext("O envio falhou. Toque na caixa acima para tentar de novo.")
end
