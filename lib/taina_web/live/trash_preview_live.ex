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
         |> assign(:video_preview_unavailable, false)}

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
        <div class="row gap-2">
          <.button kind="secondary" size="md" href={~p"/files/trash/#{@file.rkey}"} download>
            {gettext("Baixar")}
          </.button>
          <.button kind="primary" size="md" phx-click="restore">{gettext("Restaurar")}</.button>
        </div>
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
    </Layouts.page>
    """
  end
end
