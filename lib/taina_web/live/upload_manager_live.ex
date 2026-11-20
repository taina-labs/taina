defmodule TainaWeb.UploadManagerLive do
  @moduledoc """
  Stable upload owner for the authenticated LiveView session.

  The manager authenticates from its signed nested LiveView session, owns every
  upload config and input, snapshots the destination for each entry, and keeps
  the existing synchronous `Ybira.upload/3` handoff.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias Taina.Scope
  alias Taina.Ybira
  alias TainaWeb.Layouts

  @upload_names [:camera, :files, :folders]

  @impl true
  def mount(_params, %{"upload_manager_id" => <<_first::utf8, _rest::binary>> = manager_id} = session, socket) do
    case Maraca.get_session_user(session) do
      {:ok, ava} ->
        scope = Scope.for_ava(ava)
        max_blob_size = Ybira.max_blob_size()
        route_context = normalize_route_context(session["route_context"])

        if connected?(socket) do
          Phoenix.PubSub.subscribe(Taina.PubSub, Layouts.upload_manager_topic(manager_id))
        end

        socket =
          socket
          |> assign(:current_scope, scope)
          |> assign(:done, [])
          |> assign(:entry_destinations, %{})
          |> assign(:failed, [])
          |> assign(:max_blob_size, max_blob_size)
          |> assign(:quota_error?, false)
          |> assign(:route_context, route_context)
          |> allow_upload(:files,
            accept: :any,
            max_entries: 10,
            max_file_size: max_blob_size,
            auto_upload: true,
            progress: &handle_progress/3
          )
          |> allow_upload(:folders,
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

        {:ok, socket, layout: false}

      {:error, :not_authenticated} ->
        {:ok, redirect(socket, to: "/login"), layout: false}
    end
  end

  def mount(_params, _session, socket) do
    {:ok, redirect(socket, to: "/login"), layout: false}
  end

  defp normalize_route_context(%{"folder_rkey" => folder_rkey, "return_to" => return_to})
       when is_nil(folder_rkey) or is_binary(folder_rkey) do
    %{folder_rkey: folder_rkey, return_to: safe_return_to(return_to)}
  end

  defp normalize_route_context(%{folder_rkey: folder_rkey, return_to: return_to})
       when is_nil(folder_rkey) or is_binary(folder_rkey) do
    %{folder_rkey: folder_rkey, return_to: safe_return_to(return_to)}
  end

  defp normalize_route_context(_context), do: %{folder_rkey: nil, return_to: nil}

  defp safe_return_to(return_to) when is_binary(return_to), do: return_to
  defp safe_return_to(_return_to), do: nil

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, remember_upload_entries(socket)}
  end

  @impl true
  def handle_info({:upload_manager_route_context, context}, socket) do
    {:noreply, assign(socket, :route_context, normalize_route_context(context))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp remember_upload_entries(socket) do
    destinations =
      Enum.reduce(@upload_names, socket.assigns.entry_destinations, fn name, destinations ->
        socket.assigns.uploads
        |> Map.fetch!(name)
        |> Map.fetch!(:entries)
        |> Enum.reduce(destinations, fn entry, destinations ->
          Map.put_new(destinations, entry.ref, socket.assigns.route_context.folder_rkey)
        end)
      end)

    assign(socket, :entry_destinations, destinations)
  end

  defp remember_entry_destination(socket, entry) do
    update(socket, :entry_destinations, fn destinations ->
      Map.put_new(destinations, entry.ref, socket.assigns.route_context.folder_rkey)
    end)
  end

  defp forget_entry_destination(socket, entry_ref) do
    update(socket, :entry_destinations, &Map.delete(&1, entry_ref))
  end

  defp config_errors(uploads) do
    Enum.flat_map([uploads.files, uploads.folders, uploads.camera], &upload_errors/1)
  end

  defp active_upload(uploads) do
    Enum.find([uploads.files, uploads.folders, uploads.camera], uploads.files, &(&1.entries != []))
  end

  defp dropzone_state(_uploads, true), do: "error-cota"

  defp dropzone_state(uploads, _quota_error) do
    if active_upload(uploads).entries == [], do: "idle", else: "uploading"
  end

  defp finish_upload(entry, socket) do
    scope = socket.assigns.current_scope
    folder_rkey = Map.get(socket.assigns.entry_destinations, entry.ref, socket.assigns.route_context.folder_rkey)

    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok, Ybira.upload(scope, path, upload_opts(entry, folder_rkey))}
      end)

    socket = forget_entry_destination(socket, entry.ref)

    case result do
      {:ok, file} ->
        {:noreply, update(socket, :done, &[file | &1])}

      {:error, :storage_quota_exceeded} ->
        {:noreply, assign(socket, :quota_error?, true)}

      {:error, reason} ->
        {:noreply, update(socket, :failed, &[{entry.client_name, upload_error(reason)} | &1])}
    end
  end

  defp handle_progress(_name, entry, socket) do
    socket = remember_entry_destination(socket, entry)
    if entry.done?, do: finish_upload(entry, socket), else: {:noreply, socket}
  end

  defp upload_config_error(:too_large, max_blob_size),
    do: gettext("O arquivo passa de %{size}, o limite por arquivo.", size: format_bytes(max_blob_size))

  defp upload_config_error(:too_many_files, _max_blob_size),
    do: gettext("São no máximo 10 arquivos por vez. Envie o resto em seguida.")

  defp upload_config_error(_err, _max_blob_size), do: gettext("O envio falhou. Toque na caixa acima para tentar de novo.")

  defp upload_error(:mime_not_allowed),
    do: gettext("Não aceitamos este tipo de arquivo. Use imagens, PDFs, texto, áudio, vídeo ou ZIP.")

  defp upload_error(_reason), do: gettext("O envio falhou. Toque na caixa acima para tentar de novo.")

  defp upload_opts(entry, folder_rkey) do
    [
      filename: entry.client_name,
      folder_rkey: folder_rkey,
      relative_path: entry.client_relative_path
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="upload-manager-main-content" class="shell__content">
      <div id="upload-manager-panel" class="col gap-6 mx-auto w-full measure-md">
        <form
          id="upload-form"
          phx-change="validate"
          phx-submit="validate"
          phx-hook="UploadSelectionLimit"
          data-upload-max-entries="10"
        >
          <.dropzone
            id="dropzone"
            upload={active_upload(@uploads)}
            state={dropzone_state(@uploads, @quota_error?)}
            picker={active_upload(@uploads).ref == @uploads.files.ref}
            error_href={~p"/armazenamento"}
            class="w-full"
          />

          <label id="folder-input" class="dropzone hide-mobile mt-3" :if={!@quota_error?}>
            <.icon name="folder" size={28} />
            <span class="type-label text-primary">{gettext("Enviar uma pasta")}</span>
            <span class="type-caption text-muted">
              {gettext("Os arquivos mantêm a organização das pastas do seu aparelho.")}
            </span>
            <.live_file_input upload={@uploads.folders} webkitdirectory class="sr-only" />
          </label>

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
          <p class="type-overline text-error mb-2">
            {gettext("Falharam (%{count})", count: length(@failed))}
          </p>
          <ul class="list">
            <.list_row
              :for={{name, reason} <- @failed}
              kind="file"
              title={name}
              meta={reason}
              meta_class="text-error"
            >
              <:leading>
                <.service_square mark="neutral" />
              </:leading>
            </.list_row>
          </ul>
        </div>

        <div :if={@done != []}>
          <p class="type-overline text-muted mb-2">
            {gettext("Concluído (%{count})", count: length(@done))}
          </p>
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
    </main>
    """
  end
end
