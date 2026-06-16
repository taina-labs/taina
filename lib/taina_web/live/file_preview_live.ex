defmodule TainaWeb.FilePreviewLive do
  @moduledoc """
  Detalhe/preview de um arquivo (tela "Ybira - Preview"): mídia inline
  (imagem/vídeo/áudio/PDF via `/files/:id`, que já fala `Range`), metadados e
  ações: baixar, copiar link, detalhes, excluir (lixeira).
  """

  use TainaWeb, :live_view

  alias Taina.Ybira
  alias TainaWeb.Layouts

  @impl true
  def mount(%{"id" => public_id}, _session, socket) do
    case Ybira.get_file(socket.assigns.current_scope, public_id) do
      {:ok, file} ->
        {:ok,
         socket
         |> assign(:page_title, file.original_filename)
         |> assign(:file, file)
         |> assign(:text_preview, load_text_preview(file))
         |> assign(:show_details, false)
         |> assign(:show_confirm, false)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> Phoenix.LiveView.put_flash(:error, gettext("Arquivo não encontrado."))
         |> Phoenix.LiveView.redirect(to: ~p"/arquivos")}

      {:error, _reason} ->
        {:ok,
         socket
         |> Phoenix.LiveView.put_flash(:error, gettext("Não foi possível abrir o arquivo agora."))
         |> Phoenix.LiveView.redirect(to: ~p"/arquivos")}
    end
  end

  @impl true
  def handle_event("copied", _params, socket) do
    {:noreply, Phoenix.LiveView.put_flash(socket, :info, gettext("Link copiado!"))}
  end

  def handle_event("toggle-details", _params, socket) do
    {:noreply, assign(socket, :show_details, !socket.assigns.show_details)}
  end

  def handle_event("ask-delete", _params, socket) do
    {:noreply, assign(socket, :show_confirm, true)}
  end

  def handle_event("close-confirm", _params, socket) do
    {:noreply, assign(socket, :show_confirm, false)}
  end

  def handle_event("confirm-delete", _params, socket) do
    case Ybira.delete_file(socket.assigns.current_scope, socket.assigns.file.public_id) do
      {:ok, _file} ->
        {:noreply,
         socket
         |> Phoenix.LiveView.put_flash(:info, gettext("Arquivo movido para a lixeira."))
         |> Phoenix.LiveView.push_navigate(to: ~p"/arquivos")}

      {:error, _reason} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível excluir o arquivo."))}
    end
  end

  defp media_kind("image/" <> _rest), do: :image
  defp media_kind("video/" <> _rest), do: :video
  defp media_kind("audio/" <> _rest), do: :audio
  defp media_kind("application/pdf"), do: :pdf
  defp media_kind("text/" <> _rest), do: :text
  defp media_kind(_mime), do: :other

  # Pré-visualização de texto: lê até 256 KB do disco (o suficiente para a tela;
  # arquivos maiores mostram o começo). Falha de leitura: sem preview, cai no
  # ícone genérico.
  @text_preview_limit 256 * 1024

  defp load_text_preview(%{mime_type: "text/" <> _} = file) do
    case File.open(file.filepath, [:read, :binary], &IO.binread(&1, @text_preview_limit)) do
      {:ok, content} when is_binary(content) -> content
      _ -> nil
    end
  end

  defp load_text_preview(_file), do: nil

  defp file_meta(file) do
    dimensions =
      case file.metadata do
        %{"width" => w, "height" => h} -> ", #{w}x#{h}"
        _ -> ""
      end

    "#{file_kind(file.mime_type)}, #{format_bytes(file.file_size_bytes)}#{dimensions}, " <>
      gettext("enviado %{when}", when: relative_time(file.inserted_at))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_tab={:files}
      storage_stats={assigns[:storage_stats]}
    >
      <Layouts.app_bar title={@file.original_filename} back={~p"/arquivos"}>
        <:action>
          <.icon_button name="download" label={gettext("Baixar")} href={~p"/files/#{@file.public_id}"} download />
        </:action>
      </Layouts.app_bar>

      <div class="col gap-4 mx-auto w-full measure-wide">
        <div class="surface-raised radius-lg center media-frame">
          <%= case media_kind(@file.mime_type) do %>
            <% :image -> %>
              <img src={~p"/files/#{@file.public_id}"} alt={@file.original_filename} />
            <% :video -> %>
              <video controls src={~p"/files/#{@file.public_id}"} class="w-full"></video>
            <% :audio -> %>
              <audio controls src={~p"/files/#{@file.public_id}"} class="w-full p-4"></audio>
            <% :pdf -> %>
              <iframe
                src={~p"/files/#{@file.public_id}"}
                title={@file.original_filename}
                class="w-full doc-frame"
              >
              </iframe>
            <% :text -> %>
              <pre :if={@text_preview} class="text-preview">{@text_preview}</pre>
              <div :if={!@text_preview} class="empty-state">
                <.icon name="file" size={40} />
                <p class="type-body-sm">{gettext("pré-visualização indisponível")}</p>
              </div>
            <% :other -> %>
              <div class="empty-state">
                <.icon name="file" size={40} />
                <p class="type-body-sm">{gettext("pré-visualização indisponível")}</p>
              </div>
          <% end %>
        </div>

        <.card>
          <h2 class="type-h3 mb-1">{@file.original_filename}</h2>
          <p class="type-body-sm text-muted">{file_meta(@file)}</p>
          <hr class="divider my-4" />
          <div class="row between">
            <a href={~p"/files/#{@file.public_id}"} download class="viewer__action">
              <.icon name="download" size={20} />
              <span>{gettext("Baixar")}</span>
            </a>
            <button
              type="button"
              class="viewer__action"
              id="copy-file-link"
              phx-hook="Clipboard"
              data-copy={url(~p"/files/#{@file.public_id}")}
            >
              <.icon name="link" size={20} />
              <span>{gettext("Link")}</span>
            </button>
            <button type="button" class="viewer__action viewer__action--danger" phx-click="ask-delete">
              <.icon name="trash" size={20} />
              <span>{gettext("Excluir")}</span>
            </button>
            <button type="button" class="viewer__action" phx-click="toggle-details">
              <.icon name="shield" size={20} />
              <span>{gettext("Detalhes")}</span>
            </button>
          </div>
        </.card>
      </div>

      <.modal id="file-details" show={@show_details} on_cancel={JS.push("toggle-details")}>
        <h2 class="type-h3 mb-4">{gettext("Detalhes")}</h2>
        <div class="col gap-3">
          <div>
            <p class="type-caption text-faint">{gettext("Nome original")}</p>
            <p class="type-body">{@file.original_filename}</p>
          </div>
          <div>
            <p class="type-caption text-faint">{gettext("Tipo")}</p>
            <p class="type-mono-sm">{@file.mime_type}</p>
          </div>
          <div>
            <p class="type-caption text-faint">{gettext("Tamanho")}</p>
            <p class="type-body">{format_bytes(@file.file_size_bytes)}</p>
          </div>
          <div>
            <p class="type-caption text-faint">{gettext("SHA-256")}</p>
            <p class="type-mono-sm truncate">{@file.file_hash}</p>
          </div>
          <div>
            <p class="type-caption text-faint">{gettext("Enviado em")}</p>
            <p class="type-body">{Calendar.strftime(@file.inserted_at, "%d/%m/%Y %H:%M")}</p>
          </div>
        </div>
        <.button variant="secondary" class="w-full mt-6" phx-click="toggle-details">
          {gettext("Fechar")}
        </.button>
      </.modal>

      <.confirm_dialog
        id="confirm-delete"
        show={@show_confirm}
        title={gettext("Excluir \"%{name}\"?", name: @file.original_filename)}
        message={gettext("Vai para a lixeira. Dá para restaurar em até 30 dias.")}
        on_confirm="confirm-delete"
        on_cancel={JS.push("close-confirm")}
      />
    </Layouts.app>
    """
  end
end
