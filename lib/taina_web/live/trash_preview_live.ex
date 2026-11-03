defmodule TainaWeb.TrashPreviewLive do
  @moduledoc "Preview owner-only de um arquivo ainda presente na lixeira."

  use TainaWeb, :live_view

  alias Taina.Ybira
  alias TainaWeb.Layouts

  @text_preview_limit 256 * 1024

  @impl true
  def mount(%{"id" => rkey}, _session, socket) do
    scope = socket.assigns.current_scope

    case Ybira.get_trashed_file(scope, rkey) do
      {:ok, file} ->
        {:ok,
         socket
         |> assign(:page_title, gettext("Documentos"))
         |> assign(:file, file)
         |> assign(:photo_metadata, load_photo_metadata(scope, file))
         |> assign(:text_preview, load_text_preview(file))
         |> assign(:video_preview_unavailable, false)
         |> assign(:show_purge_confirm, false)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Arquivo não encontrado na lixeira."))
         |> redirect(to: ~p"/documentos/lixeira")}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Não foi possível abrir o arquivo agora."))
         |> redirect(to: ~p"/documentos/lixeira")}
    end
  end

  @impl true
  def handle_event("restore", _params, socket) do
    case Ybira.restore_file(socket.assigns.current_scope, socket.assigns.file.rkey) do
      {:ok, _file} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Arquivo restaurado."))
         |> push_navigate(to: ~p"/documentos/lixeira")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Não foi possível restaurar o arquivo."))}
    end
  end

  def handle_event("video-preview-unavailable", _params, socket) do
    {:noreply, assign(socket, :video_preview_unavailable, true)}
  end

  def handle_event("ask-purge", _params, socket), do: {:noreply, assign(socket, :show_purge_confirm, true)}
  def handle_event("close-purge", _params, socket), do: {:noreply, assign(socket, :show_purge_confirm, false)}

  def handle_event("confirm-purge", _params, socket) do
    case Ybira.purge_trash_file(socket.assigns.current_scope, socket.assigns.file.rkey) do
      {:ok, _file} ->
        {:noreply,
         socket
         |> assign(:show_purge_confirm, false)
         |> put_flash(:info, gettext("O arquivo foi apagado definitivamente."))
         |> push_navigate(to: ~p"/documentos/lixeira")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:show_purge_confirm, false)
         |> put_flash(:error, gettext("Não foi possível apagar o arquivo definitivamente."))}
    end
  end

  defp load_photo_metadata(scope, file) do
    {:ok, metadata} = Ybira.photo_metadata(scope, file)
    metadata
  end

  defp load_text_preview(%{mime: "text/" <> _} = file) do
    with {:ok, path} <- Ybira.blob_path(file),
         {:ok, device} <- File.open(path, [:read, :binary, :raw]) do
      try do
        case :file.read(device, @text_preview_limit) do
          {:ok, content} -> content
          _ -> nil
        end
      after
        :file.close(device)
      end
    else
      _ -> nil
    end
  end

  defp load_text_preview(_file), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.page
      flash={@flash}
      title={@page_title}
      back={~p"/documentos/lixeira"}
      back_label={gettext("Lixeira")}
    >
      <:action>
        <.actions_menu
          id="trash-file-actions"
          label={gettext("Mais opções para %{name}", name: @file.nome)}
          title={gettext("Ações do arquivo")}
        >
          <:item icon="download" href={~p"/files/trash/#{@file.rkey}"} download>
            {gettext("Baixar")}
          </:item>
          <:item icon="restore" click={JS.push("restore")}>{gettext("Restaurar")}</:item>
          <:item icon="trash" kind="danger" click={JS.push("ask-purge")}>
            {gettext("Apagar definitivamente")}
          </:item>
        </.actions_menu>
      </:action>

      <div class="col gap-4 mx-auto w-full measure">
        <div class="surface-raised radius-lg center media-frame col gap-2">
          <.file_preview
            file={@file}
            photo_metadata={@photo_metadata}
            text_preview={@text_preview}
            video_preview_unavailable={@video_preview_unavailable}
            download_href={~p"/files/trash/#{@file.rkey}"}
          />
          <h2 class="type-h3">{@file.nome}</h2>
          <span class="type-caption text-muted">{file_kind(@file.mime)}, {format_bytes(@file.tamanho)}</span>
        </div>

        <p class="type-body-sm text-muted">
          {gettext("Este arquivo está na lixeira. Ele será apagado depois do prazo de retenção.")}
        </p>
      </div>

      <.dialog
        id="confirm-trash-purge"
        show={@show_purge_confirm}
        kind="destructive"
        title={gettext("Apagar %{name} de vez?", name: @file.nome)}
        body={gettext("Este arquivo não poderá ser restaurado.")}
        confirm_label={gettext("Apagar definitivamente")}
        on_confirm="confirm-purge"
        on_cancel={JS.push("close-purge")}
      />
    </Layouts.page>
    """
  end
end
