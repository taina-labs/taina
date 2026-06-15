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
    folder = resolve_folder(socket.assigns.current_scope, params["pasta"])

    {:ok,
     socket
     |> assign(:page_title, gettext("Enviar arquivos"))
     |> assign(:folder, folder)
     |> assign(:done, [])
     |> assign(:failed, [])
     |> allow_upload(:files,
       accept: :any,
       max_entries: 10,
       max_file_size: @max_file_size,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  defp resolve_folder(_scope, nil), do: nil

  defp resolve_folder(scope, public_id) do
    case Ybira.get_folder(scope, public_id) do
      {:ok, folder} -> folder
      {:error, :not_found} -> nil
    end
  end

  # Consome cada arquivo assim que termina de subir; o resultado vai para a
  # lista CONCLUÍDO (ou para os erros, sem derrubar os demais envios).
  defp handle_progress(:files, entry, socket) do
    if entry.done? do
      scope = socket.assigns.current_scope
      folder = socket.assigns.folder

      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          opts = [filename: entry.client_name] ++ if folder, do: [folder_id: folder.id], else: []
          {:ok, Ybira.upload(scope, path, opts)}
        end)

      case result do
        {:ok, file} ->
          {:noreply, update(socket, :done, &[file | &1])}

        {:error, reason} ->
          {:noreply, update(socket, :failed, &[{entry.client_name, upload_error(reason)} | &1])}
      end
    else
      {:noreply, socket}
    end
  end

  defp upload_error(:mime_not_allowed), do: gettext("tipo de arquivo não permitido")
  defp upload_error(:storage_quota_exceeded), do: gettext("a cota de armazenamento acabou")
  defp upload_error(_reason), do: gettext("falha no envio")

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  def handle_event("cancel-all", _params, socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.files.entries, socket, fn entry, socket ->
        cancel_upload(socket, :files, entry.ref)
      end)

    {:noreply, socket}
  end

  defp back_path(nil), do: ~p"/arquivos"
  defp back_path(folder), do: ~p"/arquivos/pasta/#{folder.public_id}"

  defp uploading?(uploads), do: uploads.files.entries != []

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_tab={:files}
      storage_stats={assigns[:storage_stats]}
    >
      <Layouts.app_bar title={gettext("Enviar arquivos")} back={back_path(@folder)} />

      <div class="col gap-6 mx-auto w-full" style="max-width: 560px;">
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
            <span class="type-caption text-faint">
              {gettext("Imagens, PDFs e vídeos. Até 2 GB por arquivo")}
            </span>
            <.live_file_input upload={@uploads.files} class="sr-only" style="display: none;" />
          </label>
        </form>

        <div :if={uploading?(@uploads)}>
          <p class="type-overline text-faint mb-2">
            {gettext("Enviando (%{count})", count: length(@uploads.files.entries))}
          </p>
          <div class="list">
            <.list_row :for={entry <- @uploads.files.entries} title={entry.client_name}>
              <:leading>
                <% {service, icon} = file_visual(entry.client_type || "") %>
                <.service_square service={service} icon={icon} />
              </:leading>
              <:actions>
                <span class="type-caption text-brand">{entry.progress}%</span>
                <.icon_button name="close" label={gettext("Cancelar envio")} phx-click="cancel" phx-value-ref={entry.ref} />
              </:actions>
            </.list_row>
          </div>
          <div :for={entry <- @uploads.files.entries} class="mt-1">
            <.progress value={entry.progress} />
          </div>
          <p :for={err <- upload_errors(@uploads.files)} class="field__error mt-2">
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
          <p class="type-overline text-faint mb-2">{gettext("Concluído (%{count})", count: length(@done))}</p>
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
          <.button variant="primary" class="w-full" navigate={back_path(@folder)}>
            {gettext("Concluir")}
          </.button>
          <button
            :if={uploading?(@uploads)}
            type="button"
            class="type-label text-secondary text-center"
            phx-click="cancel-all"
          >
            {gettext("Cancelar tudo")}
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp upload_config_error(:too_large), do: gettext("arquivo maior que 2 GB")
  defp upload_config_error(:too_many_files), do: gettext("no máximo 10 arquivos por vez")
  defp upload_config_error(_err), do: gettext("falha no envio")
end
