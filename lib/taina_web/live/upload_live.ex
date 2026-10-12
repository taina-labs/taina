defmodule TainaWeb.UploadLive do
  @moduledoc """
  Envio de arquivos (tela "Ybira - Upload"): dropzone tracejada, progresso por
  arquivo (ENVIANDO/CONCLUÍDO), cancelamento individual e total. LiveView
  uploads com `auto_upload`; cada arquivo concluído vai direto para
  `Ybira.upload/3` (validação por magic bytes e cota acontecem lá).

  `?pasta=<public_id>` define a pasta de destino.
  """

  use TainaWeb, :live_view

  alias Taina.Ybira
  alias TainaWeb.Layouts

  @max_file_size 2 * 1024 * 1024 * 1024

  @impl true
  def mount(params, _session, socket) do
    {folder, folder_note} = resolve_folder(socket.assigns.current_scope, params["pasta"])

    socket =
      socket
      |> assign(:page_title, gettext("Enviar arquivos"))
      |> assign(:folder, folder)
      |> assign(:free_space, free_space_text(socket.assigns.storage_stats))
      |> assign(:done, [])
      |> assign(:failed, [])
      |> maybe_flash_folder_note(folder_note)

    {:ok,
     socket
     |> allow_upload(:files,
       accept: :any,
       max_entries: 10,
       max_file_size: @max_file_size,
       auto_upload: true,
       progress: &handle_progress/3
     )
     # Segunda entrada (RFC 002, Fase 3): a câmera do celular. Entrada à parte
     # para não tirar do usuário a escolha de arquivos existentes na entrada
     # principal (um único input com `capture` travaria o celular na câmera).
     # Os dois envios caem no mesmo `finish_upload/2`.
     |> allow_upload(:camera,
       accept: :any,
       max_entries: 10,
       max_file_size: @max_file_size,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  defp resolve_folder(_scope, nil), do: {nil, nil}

  # Pasta inexistente ou casa de outra pessoa: sobe para a raiz sem travar o
  # envio; o flash explica por que a pasta sumiu do cabeçalho.
  defp resolve_folder(scope, public_id) do
    case Ybira.get_folder(scope, public_id) do
      {:ok, folder} ->
        {folder, nil}

      {:error, _reason} ->
        {nil, gettext("A pasta original não está mais disponível. O envio vai para o início.")}
    end
  end

  defp maybe_flash_folder_note(socket, nil), do: socket
  defp maybe_flash_folder_note(socket, note), do: Phoenix.LiveView.put_flash(socket, :error, note)

  # Espaço livre da comunidade, em texto humano. Sem cota configurada não há
  # "livres" para mostrar (a cota infinita não avisa).
  defp free_space_text(%{quota_bytes: quota, used_bytes: used}) when is_integer(quota) do
    gettext("Espaço livre da comunidade: %{free}.", free: format_bytes(max(quota - used, 0)))
  end

  defp free_space_text(_stats), do: nil

  # Consome cada arquivo assim que termina de subir, de qualquer um dos dois
  # envios (arquivos ou câmera); o resultado vai para a lista CONCLUÍDO (ou
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

      {:error, reason} ->
        {:noreply, update(socket, :failed, &[{entry.client_name, upload_error(reason)} | &1])}
    end
  end

  defp upload_opts(entry, nil), do: [filename: entry.client_name]
  defp upload_opts(entry, folder), do: [filename: entry.client_name, folder_id: folder.id]

  # Cada erro explica o que houve e dá a saída (tom-de-voz: erros com saída,
  # sem culpa). A saída comum é a caixa de envio, no topo da tela.
  defp upload_error(:mime_not_allowed),
    do: gettext("Não aceitamos este tipo de arquivo. Use imagens, PDFs, texto, áudio, vídeo ou ZIP.")

  defp upload_error(:storage_quota_exceeded),
    do: gettext("O espaço da comunidade acabou. Quem cuida da máquina pode aumentar o limite.")

  defp upload_error(_reason), do: gettext("O envio falhou. Toque na caixa acima para tentar de novo.")

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel", %{"ref" => ref}, socket) do
    {:noreply, cancel_any(socket, ref)}
  end

  def handle_event("cancel-all", _params, socket) do
    socket =
      socket.assigns.uploads
      |> uploading_entries()
      |> Enum.reduce(socket, fn entry, socket -> cancel_any(socket, entry.ref) end)

    {:noreply, socket}
  end

  # Onde os arquivos caíram: na pasta alvo, ou no início já na aba casa (o
  # default da listagem). Cair na praça faria o recém-chegado "sumir" da tela.
  defp back_path(nil), do: ~p"/arquivos?#{[zona: "casa"]}"
  defp back_path(folder), do: ~p"/arquivos/pasta/#{folder.public_id}"

  # --- core puro: dados -> dados ---

  # O evento traz só o ref, sem dizer de qual dos dois envios a entrada veio;
  # procuramos em qual lista ela está.
  defp cancel_any(socket, ref) do
    uploads = socket.assigns.uploads

    cond do
      Enum.any?(uploads.files.entries, &(&1.ref == ref)) -> cancel_upload(socket, :files, ref)
      Enum.any?(uploads.camera.entries, &(&1.ref == ref)) -> cancel_upload(socket, :camera, ref)
      true -> socket
    end
  end

  # A fila "Enviando" junta as duas entradas, arquivos e câmera.
  defp uploading_entries(uploads), do: uploads.files.entries ++ uploads.camera.entries

  defp uploading?(uploads), do: uploading_entries(uploads) != []

  # Erros de configuração (tamanho, quantidade) somados dos dois envios.
  defp config_errors(uploads), do: upload_errors(uploads.files) ++ upload_errors(uploads.camera)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_tab={:files}
      storage_stats={assigns[:storage_stats]}
      account_alert={assigns[:account_alert] || false}
    >
      <Layouts.app_bar title={gettext("Enviar arquivos")} back={back_path(@folder)} />

      <div class="col gap-6 mx-auto w-full measure-md">
        <form id="upload-form" phx-change="validate" phx-submit="validate">
          <label
            id="dropzone"
            class="dropzone w-full"
            phx-drop-target={@uploads.files.ref}
            phx-hook="DragClass"
          >
            <.icon name="upload" size={28} />
            <span class="type-label text-primary">{gettext("Arraste arquivos aqui")}</span>
            <span class="type-label text-brand">{gettext("ou toque para escolher")}</span>
            <span class="type-caption text-muted">
              {gettext("Os arquivos entram na sua casa. Publique na praça quando quiser.")}
            </span>
            <span class="type-caption text-muted">
              {gettext("Imagens, PDFs, texto, áudio, vídeo e ZIP; até 2 GB por arquivo.")}
            </span>
            <.live_file_input upload={@uploads.files} class="sr-only" />
          </label>

          <label id="camera-input" class="dropzone hide-desktop mt-3">
            <.icon name="image" size={28} />
            <span class="type-label text-primary">{gettext("Tirar foto com a câmera")}</span>
            <span class="type-caption text-muted">
              {gettext("A foto começa na sua casa. Publique na praça para todos verem.")}
            </span>
            <.live_file_input upload={@uploads.camera} capture="environment" class="sr-only" />
          </label>
        </form>

        <p :if={@free_space} class="type-caption text-muted">{@free_space}</p>

        <div :if={uploading?(@uploads)}>
          <p class="type-overline text-muted mb-2">
            {gettext("Enviando (%{count})", count: length(uploading_entries(@uploads)))}
          </p>
          <div class="list">
            <div :for={entry <- uploading_entries(@uploads)}>
              <.list_row title={entry.client_name}>
                <:leading>
                  <% {service, icon} = file_visual(entry.client_type || "") %>
                  <.service_square service={service} icon={icon} />
                </:leading>
                <:actions>
                  <span class="type-caption text-brand">{entry.progress}%</span>
                  <.icon_button name="close" label={gettext("Cancelar envio")} phx-click="cancel" phx-value-ref={entry.ref} />
                </:actions>
              </.list_row>
              <.progress value={entry.progress} label={gettext("Enviando %{name}", name: entry.client_name)} />
            </div>
          </div>
          <p :for={err <- config_errors(@uploads)} class="field__error mt-2">
            {upload_config_error(err)}
          </p>
        </div>

        <div :if={@failed != []}>
          <p class="type-overline text-error mb-2">{gettext("Falharam (%{count})", count: length(@failed))}</p>
          <div class="list">
            <.list_row :for={{name, reason} <- @failed} title={name} meta={reason} meta_class="text-error">
              <:leading>
                <.service_square service="neutral" icon="alert" />
              </:leading>
            </.list_row>
          </div>
        </div>

        <div :if={@done != []}>
          <p class="type-overline text-muted mb-2">{gettext("Concluído (%{count})", count: length(@done))}</p>
          <div class="list">
            <.list_row
              :for={file <- @done}
              title={file.original_filename}
              meta={gettext("Concluído")}
              meta_class="text-success"
            >
              <:leading>
                <% {service, icon} = file_visual(file.mime_type) %>
                <.service_square service={service} icon={icon} />
              </:leading>
              <:actions>
                <.icon name="check" size={20} class="text-success" />
              </:actions>
            </.list_row>
          </div>
          <.progress value={100} color="success" />
        </div>

        <div class="col gap-3 mt-4">
          <%= if uploading?(@uploads) do %>
            <button type="button" class="btn btn--primary w-full" disabled>
              {gettext("Concluir")}
            </button>
            <p class="type-caption text-muted text-center">
              {gettext("Envio em andamento. Espere terminar para não perder arquivos.")}
            </p>
            <.button variant="ghost" size="sm" phx-click="cancel-all">
              {gettext("Cancelar tudo")}
            </.button>
          <% else %>
            <.button variant="primary" class="w-full" navigate={back_path(@folder)}>
              {gettext("Concluir")}
            </.button>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp upload_config_error(:too_large), do: gettext("O arquivo passa de 2 GB, o limite por arquivo.")

  defp upload_config_error(:too_many_files), do: gettext("São no máximo 10 arquivos por vez. Envie o resto em seguida.")

  defp upload_config_error(_err), do: gettext("O envio falhou. Toque na caixa acima para tentar de novo.")
end
