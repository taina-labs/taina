defmodule TainaWeb.UploadManagerLive do
  @moduledoc """
  Stable upload owner for the authenticated LiveView session.

  The manager authenticates from its signed nested LiveView session, owns every
  upload config and input, snapshots the destination for each entry, and hands
  completed browser transfers to `Ybira.Uploads.stage_and_enqueue/3`.
  """

  use TainaWeb, :live_view

  alias Taina.Config
  alias Taina.Maraca
  alias Taina.Scope
  alias Taina.Ybira
  alias Taina.Ybira.Upload
  alias Taina.Ybira.Uploads
  alias TainaWeb.Layouts

  @upload_names [:camera, :files, :folders]
  @input_keys %{
    camera: "camera",
    files: "files",
    folders: "folders"
  }
  @chunk_size 4 * 1024 * 1024
  @chunk_timeout 60_000

  @impl true
  def mount(_params, %{"upload_manager_id" => <<_first::utf8, _rest::binary>> = manager_id} = session, socket) do
    case Maraca.get_session_user(session) do
      {:ok, ava} ->
        scope = Scope.for_ava(ava)
        max_blob_size = Ybira.max_blob_size()
        max_concurrent_uploads = Config.max_concurrent_uploads()
        route_context = normalize_route_context(session["route_context"])

        if connected?(socket) do
          Uploads.subscribe(scope)
          Phoenix.PubSub.subscribe(Taina.PubSub, Layouts.upload_manager_topic(manager_id))
        end

        socket =
          socket
          |> assign(:active_queue_ids, MapSet.new())
          |> assign(:current_scope, scope)
          |> assign(:durable_uploads, [])
          |> assign(:entry_destinations, %{})
          |> assign(:entry_queue_ids, %{})
          |> assign(:entry_relative_paths, %{})
          |> assign(:entry_upload_names, %{})
          |> assign(:failed, [])
          |> assign(:finalizing_refs, MapSet.new())
          |> assign(:max_blob_size, max_blob_size)
          |> assign(:max_concurrent_uploads, max_concurrent_uploads)
          |> assign(:pending_queue_items, [])
          |> assign(:pending_queue_metadata, %{})
          |> assign(:pending_queue_revision, 0)
          |> assign(:quota_error?, false)
          |> assign(:route_context, route_context)
          |> assign(:uploads_load_error?, false)
          |> allow_upload(:files,
            accept: :any,
            max_entries: max_concurrent_uploads,
            max_file_size: max_blob_size,
            chunk_size: @chunk_size,
            chunk_timeout: @chunk_timeout,
            auto_upload: true,
            progress: &handle_progress/3
          )
          |> allow_upload(:folders,
            accept: :any,
            max_entries: max_concurrent_uploads,
            max_file_size: max_blob_size,
            chunk_size: @chunk_size,
            chunk_timeout: @chunk_timeout,
            auto_upload: true,
            progress: &handle_progress/3
          )
          |> allow_upload(:camera,
            accept: :any,
            max_entries: max_concurrent_uploads,
            max_file_size: max_blob_size,
            chunk_size: @chunk_size,
            chunk_timeout: @chunk_timeout,
            auto_upload: true,
            progress: &handle_progress/3
          )

        {:ok, reload_durable_uploads(socket), layout: false}

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

  defp normalize_queue_metadata(%{} = params) do
    queue_id = param(params, :queue_id)
    input_key = param(params, :input_key)
    destination_folder = param(params, :destination_folder)
    relative_path = param(params, :relative_path)
    client_name = param(params, :client_name)
    client_size = param(params, :client_size)

    if valid_queue_id?(queue_id) and input_key in Map.values(@input_keys) and
         valid_optional_text?(destination_folder) and is_binary(relative_path) and
         is_binary(client_name) and is_integer(client_size) and client_size >= 0 do
      {:ok,
       %{
         queue_id: queue_id,
         input_key: input_key,
         destination_folder: destination_folder,
         relative_path: relative_path,
         client_name: client_name,
         client_size: client_size
       }}
    else
      :error
    end
  end

  defp normalize_queue_metadata(_params), do: :error

  defp param(params, key), do: Map.get(params, Atom.to_string(key), Map.get(params, key))

  defp valid_queue_id?(queue_id) when is_binary(queue_id) and byte_size(queue_id) in 1..64, do: true
  defp valid_queue_id?(_queue_id), do: false

  defp valid_optional_text?(nil), do: true
  defp valid_optional_text?(value) when is_binary(value), do: true
  defp valid_optional_text?(_value), do: false

  defp normalize_pending_report(params) do
    revision = param(params, :revision)
    items = param(params, :items)

    if is_integer(revision) and revision >= 0 and is_list(items) do
      {:ok, revision, deduplicate_pending_items(items)}
    else
      :error
    end
  end

  defp deduplicate_pending_items(items) do
    {pending, _seen} = Enum.reduce(items, {[], MapSet.new()}, &collect_pending_item/2)
    Enum.reverse(pending)
  end

  defp collect_pending_item(item, {pending, seen}) do
    case normalize_pending_item(item) do
      {:ok, item} ->
        if MapSet.member?(seen, item.queue_id) do
          {pending, seen}
        else
          {[item | pending], MapSet.put(seen, item.queue_id)}
        end

      :error ->
        {pending, seen}
    end
  end

  defp normalize_pending_item(%{} = item) do
    queue_id = param(item, :queue_id)
    input_key = param(item, :input_key)
    name = param(item, :name)
    size = param(item, :size)
    destination_folder = param(item, :destination_folder)
    relative_path = param(item, :relative_path)

    if valid_queue_id?(queue_id) and input_key in Map.values(@input_keys) and is_binary(name) and
         is_integer(size) and size >= 0 and valid_optional_text?(destination_folder) and
         is_binary(relative_path) do
      {:ok,
       %{
         queue_id: queue_id,
         input_key: input_key,
         name: name,
         size: size,
         destination_folder: destination_folder,
         relative_path: relative_path
       }}
    else
      :error
    end
  end

  defp normalize_pending_item(_item), do: :error

  @impl true
  def handle_event("validate", _params, socket) do
    socket =
      socket
      |> remember_upload_entries()
      |> release_rejected_entries()

    {:noreply, socket}
  end

  def handle_event("upload_queue_item", params, socket) do
    case normalize_queue_metadata(params) do
      {:ok, metadata} ->
        queue =
          :queue.in(
            metadata,
            Map.get(socket.assigns.pending_queue_metadata, metadata.input_key, :queue.new())
          )

        pending = Map.put(socket.assigns.pending_queue_metadata, metadata.input_key, queue)

        {:noreply,
         socket
         |> assign(:pending_queue_metadata, pending)
         |> update(:active_queue_ids, &MapSet.put(&1, metadata.queue_id))}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("upload_queue_pending", params, socket) do
    case normalize_pending_report(params) do
      {:ok, revision, items} when revision > socket.assigns.pending_queue_revision ->
        {:noreply,
         socket
         |> assign(:pending_queue_revision, revision)
         |> assign(:pending_queue_items, items)}

      _stale_or_invalid ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_pending_upload", params, socket) do
    queue_id = param(params, :queue_id)
    {cancelled, pending} = Enum.split_with(socket.assigns.pending_queue_items, &(&1.queue_id == queue_id))

    if cancelled == [] do
      {:noreply, socket}
    else
      socket =
        socket
        |> assign(:pending_queue_items, pending)
        |> push_event("upload_queue_cancel", %{queue_id: queue_id})

      {:noreply, socket}
    end
  end

  def handle_event("cancel_active_upload", params, socket) do
    case Map.get(socket.assigns.entry_upload_names, param(params, :entry_ref)) do
      nil ->
        {:noreply, socket}

      upload_name ->
        entry_ref = param(params, :entry_ref)
        queue_id = Map.get(socket.assigns.entry_queue_ids, entry_ref)

        socket =
          socket
          |> Phoenix.LiveView.cancel_upload(upload_name, entry_ref)
          |> release_entry_context(entry_ref)
          |> maybe_push_queue_cancel(queue_id)

        {:noreply, socket}
    end
  end

  defp maybe_push_queue_cancel(socket, queue_id) when is_binary(queue_id),
    do: push_event(socket, "upload_queue_cancel", %{queue_id: queue_id})

  defp maybe_push_queue_cancel(socket, _queue_id), do: socket

  @impl true
  def handle_info({:upload_manager_route_context, context}, socket) do
    {:noreply,
     socket
     |> assign(:route_context, normalize_route_context(context))
     |> assign(:quota_error?, false)}
  end

  def handle_info({:upload_manager_visibility, visible?}, socket) when is_boolean(visible?) do
    {:noreply, push_event(socket, "upload_manager_visibility", %{visible: visible?})}
  end

  def handle_info({:ybira_upload, _public_id, _state}, socket) do
    {:noreply, reload_durable_uploads(socket)}
  end

  def handle_info({:finalize_upload, entry_ref}, socket) do
    case find_upload_entry(socket, entry_ref) do
      {name, %{done?: true} = entry} ->
        finish_upload(name, entry, socket)

      _missing_or_incomplete ->
        {:noreply, release_entry_context(socket, entry_ref)}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp remember_upload_entries(socket) do
    Enum.reduce(@upload_names, socket, fn name, socket ->
      socket.assigns.uploads
      |> Map.fetch!(name)
      |> Map.fetch!(:entries)
      |> Enum.reduce(socket, fn entry, socket ->
        maybe_remember_entry_context(socket, name, entry)
      end)
    end)
  end

  defp maybe_remember_entry_context(socket, name, entry) do
    if Map.has_key?(socket.assigns.entry_destinations, entry.ref) do
      socket
    else
      {metadata, socket} = take_queue_metadata(socket, Map.fetch!(@input_keys, name))

      folder_rkey =
        case metadata do
          %{destination_folder: destination_folder} -> destination_folder
          nil -> socket.assigns.route_context.folder_rkey
        end

      relative_path =
        case metadata do
          %{relative_path: relative_path} -> relative_path
          nil -> entry.client_relative_path
        end

      socket
      |> update(:entry_destinations, &Map.put_new(&1, entry.ref, folder_rkey))
      |> update(:entry_relative_paths, &Map.put_new(&1, entry.ref, relative_path))
      |> update(:entry_upload_names, &Map.put_new(&1, entry.ref, name))
      |> maybe_remember_entry_queue_id(entry.ref, metadata)
    end
  end

  defp take_queue_metadata(socket, input_key) do
    case :queue.out(Map.get(socket.assigns.pending_queue_metadata, input_key, :queue.new())) do
      {:empty, _queue} ->
        {nil, socket}

      {{:value, metadata}, queue} ->
        pending_queue_metadata =
          if :queue.is_empty(queue) do
            Map.delete(socket.assigns.pending_queue_metadata, input_key)
          else
            Map.put(socket.assigns.pending_queue_metadata, input_key, queue)
          end

        {metadata, assign(socket, :pending_queue_metadata, pending_queue_metadata)}
    end
  end

  defp maybe_remember_entry_queue_id(socket, _entry_ref, nil), do: socket

  defp maybe_remember_entry_queue_id(socket, entry_ref, %{queue_id: queue_id}) do
    update(socket, :entry_queue_ids, &Map.put_new(&1, entry_ref, queue_id))
  end

  defp release_rejected_entries(socket) do
    Enum.reduce(@upload_names, socket, fn name, socket ->
      config = Map.fetch!(socket.assigns.uploads, name)

      Enum.reduce(config.entries, socket, fn entry, socket ->
        release_rejected_entry(config, entry, socket)
      end)
    end)
  end

  defp release_rejected_entry(config, entry, socket) do
    if upload_errors(config, entry) == [], do: socket, else: release_entry_context(socket, entry.ref)
  end

  defp find_upload_entry(socket, entry_ref) do
    Enum.find_value(@upload_names, fn name ->
      case Enum.find(Map.fetch!(socket.assigns.uploads, name).entries, &(&1.ref == entry_ref)) do
        nil -> nil
        entry -> {name, entry}
      end
    end)
  end

  defp release_entry_context(socket, entry_ref) do
    queue_id = Map.get(socket.assigns.entry_queue_ids, entry_ref)

    socket
    |> update(:entry_destinations, &Map.delete(&1, entry_ref))
    |> update(:entry_queue_ids, &Map.delete(&1, entry_ref))
    |> update(:entry_relative_paths, &Map.delete(&1, entry_ref))
    |> update(:entry_upload_names, &Map.delete(&1, entry_ref))
    |> update(:finalizing_refs, &MapSet.delete(&1, entry_ref))
    |> maybe_release_queue_id(queue_id)
  end

  defp maybe_release_queue_id(socket, nil), do: socket

  defp maybe_release_queue_id(socket, queue_id) do
    update(socket, :active_queue_ids, &MapSet.delete(&1, queue_id))
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

  defp finish_upload(_name, entry, socket) do
    scope = socket.assigns.current_scope

    folder_rkey =
      Map.get(socket.assigns.entry_destinations, entry.ref, socket.assigns.route_context.folder_rkey)

    relative_path = Map.get(socket.assigns.entry_relative_paths, entry.ref, entry.client_relative_path)

    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok,
         Uploads.stage_and_enqueue(scope, path, %{
           filename: entry.client_name,
           size: entry.client_size,
           folder_rkey: folder_rkey,
           relative_path: relative_path
         })}
      end)

    socket = release_entry_context(socket, entry.ref)

    case result do
      {:ok, %Upload{}} ->
        {:noreply, reload_durable_uploads(socket)}

      {:error, :storage_quota_exceeded} ->
        {:noreply, assign(socket, :quota_error?, true)}

      {:error, reason} ->
        failed = [{entry.client_name, upload_error(reason)} | socket.assigns.failed]
        {:noreply, assign(socket, :failed, failed)}
    end
  end

  defp handle_progress(name, entry, socket) do
    socket = maybe_remember_entry_context(socket, name, entry)

    if entry.done? do
      {:noreply, queue_finalization(socket, entry.ref)}
    else
      {:noreply, socket}
    end
  end

  defp queue_finalization(socket, entry_ref) do
    if MapSet.member?(socket.assigns.finalizing_refs, entry_ref) do
      socket
    else
      socket = update(socket, :finalizing_refs, &MapSet.put(&1, entry_ref))
      send(self(), {:finalize_upload, entry_ref})
      socket
    end
  end

  defp reload_durable_uploads(socket) do
    case Uploads.list(socket.assigns.current_scope) do
      {:ok, uploads} ->
        socket
        |> assign(:durable_uploads, uploads)
        |> assign(:uploads_load_error?, false)

      {:error, _reason} ->
        socket
        |> assign(:durable_uploads, [])
        |> assign(:uploads_load_error?, true)
    end
  end

  defp active_queue_ids(%MapSet{} = ids), do: ids |> MapSet.to_list() |> Enum.sort() |> Enum.join(" ")

  defp active_entry_finalizing?(uploads, finalizing_refs) do
    case Enum.find(active_upload(uploads).entries, & &1.done?) do
      nil -> false
      entry -> MapSet.member?(finalizing_refs, entry.ref)
    end
  end

  defp cancellable_upload_entries(uploads, finalizing_refs) do
    Enum.flat_map(@upload_names, fn name ->
      uploads
      |> Map.fetch!(name)
      |> Map.fetch!(:entries)
      |> Enum.reject(fn entry ->
        entry.done? or MapSet.member?(finalizing_refs, entry.ref)
      end)
      |> Enum.map(fn entry ->
        %{ref: entry.ref, name: entry.client_name, progress: entry.progress}
      end)
    end)
  end

  defp pending_upload_meta(item) do
    gettext("Aguardando para enviar, %{size}", size: format_bytes(item.size))
  end

  defp upload_state_text(%Upload{state: :queued}), do: gettext("Na fila")
  defp upload_state_text(%Upload{state: :processing}), do: gettext("Guardando na casa...")
  defp upload_state_text(%Upload{state: :completed}), do: gettext("Concluído")
  defp upload_state_text(%Upload{state: :failed, error_code: code}), do: upload_error(code)

  defp upload_state_class(%Upload{state: :completed}), do: "text-success"
  defp upload_state_class(%Upload{state: :failed}), do: "text-error"
  defp upload_state_class(_upload), do: "text-muted"

  defp upload_groups(uploads) do
    Enum.flat_map([:queued, :processing, :completed, :failed], fn state ->
      state_uploads = Enum.filter(uploads, &(&1.state == state))

      if state_uploads == [] do
        []
      else
        [%{state: state, uploads: state_uploads, title: upload_group_title(state, length(state_uploads))}]
      end
    end)
  end

  defp upload_group_title(:queued, count), do: gettext("Na fila (%{count})", count: count)
  defp upload_group_title(:processing, count), do: gettext("Guardando na casa (%{count})", count: count)
  defp upload_group_title(:completed, count), do: gettext("Concluído (%{count})", count: count)
  defp upload_group_title(:failed, count), do: gettext("Falharam (%{count})", count: count)

  defp upload_group_class(:completed), do: "text-success"
  defp upload_group_class(:failed), do: "text-error"
  defp upload_group_class(_state), do: "text-muted"

  defp upload_config_error(:too_large, max_blob_size, _max_concurrent_uploads),
    do: gettext("O arquivo passa de %{size}, o limite por arquivo.", size: format_bytes(max_blob_size))

  defp upload_config_error(:too_many_files, _max_blob_size, max_concurrent_uploads),
    do: gettext("São no máximo %{count} arquivos por vez. Envie o resto em seguida.", count: max_concurrent_uploads)

  defp upload_config_error(_err, _max_blob_size, _max_concurrent_uploads),
    do: gettext("O envio falhou. Toque na caixa acima para tentar de novo.")

  defp upload_error(:storage_quota_exceeded),
    do: gettext("O espaço da comunidade acabou. Peça a quem cuida da nuvem para liberar.")

  defp upload_error(:blob_too_large), do: gettext("O arquivo passa do limite por arquivo.")

  defp upload_error(reason) when reason in [:mime_not_allowed, :invalid_mime],
    do: gettext("Não aceitamos este tipo de arquivo. Use imagens, PDFs, texto, áudio, vídeo ou ZIP.")

  defp upload_error(:folder_unavailable),
    do: gettext("A pasta original não está mais disponível. Envie o arquivo de novo.")

  defp upload_error(reason) when reason in [:staging_missing, :staging_invalid, :staging_failed],
    do: gettext("O arquivo não pôde ser guardado. Envie-o de novo.")

  defp upload_error(_reason), do: gettext("O envio falhou. Toque na caixa acima para tentar de novo.")

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :cancellable_uploads,
        cancellable_upload_entries(assigns.uploads, assigns.finalizing_refs)
      )

    ~H"""
    <main id="upload-manager-main-content" class="shell__content">
      <div id="upload-manager-panel" class="col gap-6 mx-auto w-full measure-md">
        <form
          id="upload-form"
          phx-change="validate"
          phx-submit="validate"
          phx-hook="UploadQueueHook"
          data-upload-queue-event="upload_queue_item"
          data-upload-queue-max-concurrent={@max_concurrent_uploads}
          data-upload-queue-active-ids={active_queue_ids(@active_queue_ids)}
          data-upload-queue-folder={@route_context.folder_rkey || ""}
        >
          <label
            :if={dropzone_state(@uploads, @quota_error?) == "idle"}
            id="dropzone"
            class="dropzone w-full"
            phx-drop-target={@uploads.files.ref}
            phx-hook="DragClass"
          >
            <.icon name="upload" size={28} />
            <span class="dropzone__title dropzone__title--idle">
              {gettext("Toque para escolher")}
            </span>
            <span class="dropzone__title dropzone__title--drag">
              {gettext("Solte para enviar")}
            </span>
            <span class="dropzone__hint">
              {gettext("Ou arraste os arquivos. Vai para a casa: só entra quem você deixar.")}
            </span>
            <span class="dropzone__cta">{gettext("Escolher arquivos")}</span>
            <.live_file_input
              :for={upload <- [@uploads.files]}
              upload={upload}
              class="sr-only"
              data-upload-queue-input="files"
            />
          </label>

          <.dropzone
            :if={dropzone_state(@uploads, @quota_error?) != "idle"}
            id="dropzone"
            upload={active_upload(@uploads)}
            state={dropzone_state(@uploads, @quota_error?)}
            picker={false}
            finalizing={active_entry_finalizing?(@uploads, @finalizing_refs)}
            error_href={~p"/armazenamento"}
            class="w-full"
          />

          <.live_file_input
            :if={
              !@quota_error? and dropzone_state(@uploads, @quota_error?) == "uploading" and
                active_upload(@uploads).ref == @uploads.files.ref
            }
            upload={@uploads.files}
            class="sr-only"
            data-upload-queue-input="files"
          />

          <label id="folder-input" class="dropzone hide-mobile mt-3" :if={!@quota_error?}>
            <.icon name="folder" size={28} />
            <span class="type-label text-primary">{gettext("Enviar uma pasta")}</span>
            <span class="type-caption text-muted">
              {gettext("Os arquivos mantêm a organização das pastas do seu aparelho.")}
            </span>
            <.live_file_input
              upload={@uploads.folders}
              webkitdirectory
              class="sr-only"
              data-upload-queue-input="folders"
            />
          </label>

          <label id="camera-input" class="dropzone hide-desktop mt-3" :if={!@quota_error?}>
            <.icon name="image" size={28} />
            <span class="type-label text-primary">{gettext("Tirar foto com a câmera")}</span>
            <span class="type-caption text-muted">
              {gettext("A foto começa na sua casa. Publique na praça para todos verem.")}
            </span>
            <.live_file_input
              upload={@uploads.camera}
              capture="environment"
              class="sr-only"
              data-upload-queue-input="camera"
            />
          </label>

          <p :for={err <- config_errors(@uploads)} class="field__error mt-2">
            {upload_config_error(err, @max_blob_size, @max_concurrent_uploads)}
          </p>
        </form>

        <div :if={@cancellable_uploads != []} class="col gap-2">
          <ul class="list">
            <.list_row
              :for={entry <- @cancellable_uploads}
              id={"active-upload-#{entry.ref}"}
              kind="file"
              title={entry.name}
              meta={gettext("Enviando %{progress}%", progress: entry.progress)}
            >
              <:leading>
                <.service_square mark="neutral" />
              </:leading>
              <:actions>
                <.button
                  kind="secondary"
                  size="md"
                  aria-label={gettext("Cancelar o envio de %{name}", name: entry.name)}
                  phx-click="cancel_active_upload"
                  phx-value-entry-ref={entry.ref}
                >
                  {gettext("Cancelar")}
                </.button>
              </:actions>
            </.list_row>
          </ul>
        </div>

        <div :if={@pending_queue_items != []} id="pending-upload-queue" class="col gap-2">
          <p class="type-overline text-muted">
            {gettext("Aguardando para enviar (%{count})", count: length(@pending_queue_items))}
          </p>
          <ul class="list">
            <.list_row
              :for={item <- @pending_queue_items}
              id={"pending-upload-#{item.queue_id}"}
              kind="file"
              title={item.name}
              meta={pending_upload_meta(item)}
            >
              <:leading>
                <.service_square mark="neutral" />
              </:leading>
              <:actions>
                <.button
                  kind="secondary"
                  size="md"
                  aria-label={gettext("Cancelar o envio de %{name}", name: item.name)}
                  phx-click="cancel_pending_upload"
                  phx-value-queue_id={item.queue_id}
                >
                  {gettext("Cancelar")}
                </.button>
              </:actions>
            </.list_row>
          </ul>
        </div>

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

        <p :if={@uploads_load_error?} class="field__error" role="status">
          {gettext("Não foi possível carregar os envios recentes.")}
        </p>

        <div :for={group <- upload_groups(@durable_uploads)}>
          <p class={["type-overline mb-2", upload_group_class(group.state)]}>{group.title}</p>
          <ul class="list">
            <.list_row
              :for={upload <- group.uploads}
              kind="file"
              title={upload.filename}
              meta={upload_state_text(upload)}
              meta_class={upload_state_class(upload)}
            >
              <:leading>
                <.service_square mark="neutral" />
              </:leading>
              <:actions :if={upload.state == :completed}>
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
