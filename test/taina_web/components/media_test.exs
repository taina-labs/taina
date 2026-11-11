defmodule TainaWeb.UI.MediaTest do
  @moduledoc """
  Testes dos componentes de mídia (Wave 1c): viewer (markup movido da
  Galeria, comportamento preservado) e dropzone nos 5 estados do Penpot.
  """

  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import TainaWeb.UI.Media

  alias Phoenix.LiveView.UploadConfig

  defp viewer_component(assigns) do
    ~H"""
    <.viewer
      file={@file}
      photo_ids={@photo_ids}
      zona={@zona}
      link="/files/abc"
      src="/files/abc"
      src_md="/files/abc/thumbnail/md"
    />
    """
  end

  defp dropzone_component(assigns) do
    ~H"""
    <.dropzone upload={@upload} state={@state} error_href={@error_href} retry={@retry} />
    """
  end

  defp build_upload(entries) do
    :files
    |> UploadConfig.build("phx-ref-1",
      accept: :any,
      max_entries: 10,
      max_file_size: 2_000_000_000,
      auto_upload: true,
      progress: fn _name, _entry, socket -> {:noreply, socket} end
    )
    |> struct!(entries: entries)
  end

  defp build_entry(name, size, progress, ref \\ "phx-e1") do
    %Phoenix.LiveView.UploadEntry{
      ref: ref,
      client_name: name,
      client_size: size,
      client_type: "image/jpeg",
      progress: progress
    }
  end

  @viewer_file %{
    rkey: "abc",
    nome: "trilha-da-praia.jpg",
    mime: "image/jpeg",
    tamanho: 1_000,
    hash: "sha256-aaaa",
    inserted_at: ~N[2026-10-04 00:00:00]
  }

  defp viewer_html(opts \\ []) do
    assigns =
      Enum.into(opts, %{
        file: @viewer_file,
        photo_ids: ["bcd", "abc"],
        zona: :casa,
        link: "/files/abc",
        src: "/files/abc",
        src_md: "/files/abc/thumbnail/md"
      })

    render_component(&viewer_component/1, assigns)
  end

  defp dropzone_html(state, opts \\ []) do
    assigns =
      Enum.into(opts, %{
        upload: build_upload([]),
        state: state,
        error_href: nil,
        retry: nil
      })

    render_component(&dropzone_component/1, assigns)
  end

  # ---------- Viewer ----------

  test "viewer: dialog fullscreen com ViewerNav, legenda e contador" do
    html = viewer_html()

    assert html =~ ~S(class="viewer")
    assert html =~ ~S(role="dialog")
    assert html =~ ~S(aria-modal="true")
    assert html =~ ~S(aria-label="Visualizador de fotos")
    assert html =~ ~S(phx-hook="ViewerNav")
    assert html =~ "trilha-da-praia.jpg"
    assert html =~ "04/10/2026"
    assert html =~ "2 de 2"
  end

  test "viewer: id do painel preservado" do
    assert viewer_html() =~ ~S(id="viewer")
  end

  test "viewer: FECHAR no cabeçalho, sem barra de ações" do
    html = viewer_html()

    assert html =~ ~S(aria-label="Fechar")
    assert html =~ ~S(phx-click="close")
    assert html =~ ~S(id="viewer-close")

    # o board não tem ações no visualizador: elas moram em /documentos/:id
    refute html =~ "viewer__actions"
    refute html =~ ~S(id="viewer-copy-link")
  end

  test "viewer: legenda do board traz nome, data e zona" do
    html = viewer_html(zona: :praca)

    assert html =~ "trilha-da-praia.jpg, 04/10/2026, na praça"
    assert html =~ "2 de 2"
  end

  test "viewer: full swap só dentro do techo do Pi; sem troca de imagem fora" do
    html = viewer_html()

    # 1_000 bytes cabem: troca entra
    assert html =~ ~S(id="viewer-full-swap")
    assert html =~ ~S(phx-hook="FullSwap")
    assert html =~ ~S(src="/files/abc/thumbnail/md")
    assert html =~ ~S(data-full="/files/abc")

    grande = Map.put(@viewer_file, :tamanho, 30 * 1024 * 1024)
    html = viewer_html(file: grande)

    assert html =~ ~S(src="/files/abc/thumbnail/md")
  end

  test "viewer: vídeo troca img por video tag" do
    video = Map.put(@viewer_file, :mime, "video/mp4")
    html = viewer_html(file: video)

    assert html =~ "<video"
    refute html =~ "viewer-full-swap"
  end

  test "viewer: navegação escondida com uma foto só, setas com duas" do
    solo = viewer_html(photo_ids: ["abc"])

    refute solo =~ "viewer__nav"

    par = viewer_html()

    assert par =~ "viewer__nav--prev"
    assert par =~ "viewer__nav--next"
  end

  # ---------- Dropzone ----------

  test "dropzone idle: label de arrasto com convites do board e CTA" do
    html = dropzone_html("idle")

    assert html =~ "<label"
    assert html =~ "phx-drop-target"
    assert html =~ "Toque para escolher"
    assert html =~ "Solte para enviar"
    assert html =~ "Ou arraste os arquivos. Vai para a casa: só entra quem você deixar."
    assert html =~ "Escolher arquivos"
    assert html =~ "dropzone__title"
    assert html =~ "dropzone__cta"
  end

  test "dropzone uploading: Enviando com nome, %, progresso e Guardando na casa" do
    upload =
      build_upload([build_entry("trilha-da-praia.jpg", 6_500_000, 64)])

    html = dropzone_html("uploading", upload: upload)

    assert html =~ "Enviando trilha-da-praia.jpg"
    assert html =~ "64%"
    assert html =~ "Guardando na casa. "
    assert html =~ "4,0 MB de 6,2 MB"
    assert html =~ "progress"
  end

  test "dropzone error-cota: título, copy do Ver espaço e link de armazenamento" do
    html = dropzone_html("error-cota", error_href: "/armazenamento")

    assert html =~ "Não deu para enviar"
    assert html =~ "O espaço da comunidade acabou. Peça a quem cuida da nuvem para liberar."
    assert html =~ "Ver espaço"
    assert html =~ ~S(href="/armazenamento")
    assert html =~ "dropzone--error-cota"
  end

  test "dropzone error-rede: copy do Tentar de novo com evento" do
    html = dropzone_html("error-rede", retry: "retry")

    assert html =~ "Não deu para enviar"
    assert html =~ "A conexão caiu no meio do envio. O arquivo não saiu da sua casa."
    assert html =~ "Tentar de novo"
    assert html =~ "phx-click=\"retry\""
    assert html =~ "dropzone--error-rede"
  end

  test "dropzone error-rede: só com retry, sem link de espaço" do
    html = dropzone_html("error-rede", retry: "retry")
    assert html =~ "Tentar de novo"
    refute html =~ "Ver espaço"
    refute html =~ "href=\"/armazenamento\""
  end

  test "dropzone: o gatilho de arrastra fica no idle pelo phx-hook" do
    assert dropzone_html("idle") =~ "phx-hook=\"DragClass\""
  end

  test "dropzone erro de cota: sem gatilho, sem ação" do
    html = dropzone_html("error-cota")

    assert html =~ "dropzone--error-cota"
    refute html =~ "Ver espaço"
    refute html =~ "Tentar de novo"
  end
end
