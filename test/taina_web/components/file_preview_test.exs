defmodule TainaWeb.UI.FilePreviewTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import TainaWeb.UI.FilePreview

  @video_file %{rkey: "abc", nome: "video.mkv", mime: "video/x-matroska", tamanho: 100}

  defp component(assigns) do
    ~H"""
    <.file_preview
      file={@file}
      photo_metadata={@photo_metadata}
      text_preview={@text_preview}
      video_preview_unavailable={@video_preview_unavailable}
      download_href="/files/abc"
    />
    """
  end

  defp render_preview(overrides \\ %{}) do
    assigns =
      Enum.into(overrides, %{
        file: @video_file,
        photo_metadata: %{},
        text_preview: nil,
        video_preview_unavailable: false
      })

    render_component(&component/1, assigns)
  end

  test "video preview includes the capability hook" do
    html = render_preview()

    assert html =~ ~S(phx-hook="VideoFallback")
    assert html =~ ~S(data-video-mime="video/x-matroska")
  end

  test "unsupported video state offers a download" do
    html = render_preview(%{video_preview_unavailable: true})

    refute html =~ ~S(phx-hook="VideoFallback")
    assert html =~ ~S(a href="/files/abc" download)
    assert html =~ "Este navegador não consegue tocar este vídeo."
  end
end
