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
      own={@own}
      zona={@zona}
      link="/files/abc"
      src="/files/abc"
      src_md="/files/abc/thumbnail/md"
      rail={@rail}
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
        own: true,
        zona: :casa,
        rail: []
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

    assert html =~ ~s(class="viewer")
    assert html =~ ~s(role="dialog")
    assert html =~ ~s(aria-modal="true")
    assert html =~ ~s(aria-label="Visualizador de fotos")
    assert html =~ ~s(phx-hook="ViewerNav")
    assert html =~ "trilha-da-praia.jpg"
    assert html =~ "04/10/2026"
    assert html =~ "2 de 2"
  end

  test "viewer: id do painel preservado" do
    assert viewer_html() =~ ~s(id="viewer")
  end

  test "viewer: FECHAR e copiar link no cabeçalho" do
    html = viewer_html()

    assert html =~ ~s(aria-label="Fechar")
    assert html =~ ~s(phx-click="close")
    assert html =~ ~s(id="viewer-close")
    assert html =~ ~s(aria-label="Copiar link")
    assert html =~ ~s(data-copy="/files/abc")
    assert html =~ ~s(id="viewer-copy-link")
  end

  test "viewer: full swap só dentro do techo do Pi; sem troca de imagem fora" do
    html = viewer_html()

    # 1_000 bytes cabem: troca entra
    assert html =~ ~s(id="viewer-full-swap")
    assert html =~ ~s(phx-hook="FullSwap")
    assert html =~ ~s(src="/files/abc/thumbnail/md")
    assert html =~ ~s(data-full="/files/abc")

    grande = Map.put(@viewer_file, :tamanho, 30 * 1024 * 1024)
    html = viewer_html(file: grande)

    assert html =~ ~s(src="/files/abc/thumbnail/md")
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

  test "viewer: trilha de fotos vizinhas embaixo do board" do
    rail = viewer_rail(["bcd", "abc", "dfg"], "abc")
    html = viewer_html(photo_ids: ["bcd", "abc", "dfg"], rail: rail)

    assert html =~ "viewer__rail"
    assert html =~ "aria-current"
    assert html =~ "/files/bcd/thumbnail/sm"
  end

  test "viewer: ações de próprio dono (publicar na praça) e alheias" do
    html = viewer_html(own: true, zona: :casa)

    assert html =~ "Publicar na praça"
    assert html =~ ~s(phx-click="ask-zona")
    # sem dono: a alavanca da zona não desenha

    html = viewer_html(own: false)

    refute html =~ "ask-zona"

    html = viewer_html(own: true, zona: :praca)

    assert html =~ "Tirar da praça"
  end

  test "viewer: ações do rodapé (Compartilhar, Baixar, Detalhes, Excluir)" do
    html = viewer_html()

    assert html =~ ~s(id="viewer-share")
    assert html =~ "Compartilhar"
    assert html =~ ~s(download)
    assert html =~ "Baixar"
    assert html =~ "Detalhes"
    assert html =~ "Excluir"
    assert html =~ "viewer__action--danger"
  end

  test "viewer_rail: janela em volta da atual, posições 1-based" do
    rail = viewer_rail(["a", "b", "c", "d", "e"], "c")

    assert [
             %{id: "a", position: 1},
             %{id: "b", position: 2},
             %{id: "c", position: 3},
             %{id: "d", position: 4},
             %{id: "e", position: 5}
           ] = rail

    assert Enum.all?(rail, &String.starts_with?(&1.thumb, "/files/"))
    assert Enum.all?(rail, &String.starts_with?(&1.patch, "/fotos/"))
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
    assert html =~ ~s(href="/armazenamento")
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
