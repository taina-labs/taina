defmodule TainaWeb.UI.FilePreview do
  @moduledoc "Preview inline de arquivos legíveis pelo navegador."

  use Phoenix.Component
  use Gettext, backend: TainaWeb.Gettext

  import TainaWeb.UI.Actions, only: [button: 1]
  import TainaWeb.UI.Content, only: [service_square: 1]

  attr :file, :any, required: true
  attr :photo_metadata, :map, default: %{}
  attr :text_preview, :any, default: nil
  attr :video_preview_unavailable, :boolean, default: false
  attr :download_href, :string, required: true

  def file_preview(assigns) do
    ~H"""
    <%= case media_kind(@file.mime) do %>
      <% :image -> %>
        <img
          src={@download_href}
          alt={@file.nome}
          width={file_dimension(@photo_metadata, "width")}
          height={file_dimension(@photo_metadata, "height")}
        />
      <% :video -> %>
        <video
          :if={!@video_preview_unavailable}
          id={"file-preview-video-#{@file.rkey}"}
          controls
          playsinline
          src={@download_href}
          data-video-mime={@file.mime}
          phx-hook="VideoFallback"
          class="w-full"
        ></video>
        <div :if={@video_preview_unavailable} class="col gap-3 center p-6" role="status">
          <.service_square mark="video" size="lg" />
          <p class="type-body-sm text-muted text-center">
            {gettext("Este navegador não consegue tocar este vídeo.")}
          </p>
          <.button kind="secondary" size="md" href={@download_href} download>
            {gettext("Baixar")}
          </.button>
        </div>
      <% :audio -> %>
        <audio controls src={@download_href} class="w-full p-4"></audio>
      <% :pdf -> %>
        <iframe src={@download_href} title={@file.nome} class="w-full doc-frame"></iframe>
      <% :text -> %>
        <pre :if={@text_preview} class="text-preview">{@text_preview}</pre>
        <.service_square :if={!@text_preview} mark="doc" size="lg" />
      <% :other -> %>
        <.service_square mark="doc" size="lg" />
    <% end %>
    """
  end

  defp media_kind("image/" <> _rest), do: :image
  defp media_kind("video/" <> _rest), do: :video
  defp media_kind("audio/" <> _rest), do: :audio
  defp media_kind("application/pdf"), do: :pdf
  defp media_kind("text/" <> _rest), do: :text
  defp media_kind(_mime), do: :other

  defp file_dimension(metadata, "width") do
    case metadata do
      %{"width" => width, "height" => _height} -> width
      _ -> nil
    end
  end

  defp file_dimension(metadata, "height") do
    case metadata do
      %{"width" => _width, "height" => height} -> height
      _ -> nil
    end
  end
end
