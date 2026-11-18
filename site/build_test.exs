ExUnit.start()

defmodule TainaSiteBuildTest do
  use ExUnit.Case, async: false

  @build_script Path.expand("build.exs", __DIR__)
  @opencode_temporary_root "/private/var/folders/vn/5s9hnph912z0cx4zz04w_cch0000gn/T/opencode"
  @temporary_root if(File.dir?(@opencode_temporary_root),
                    do: @opencode_temporary_root,
                    else: System.tmp_dir!()
                  )

  test "renders editorial pages and documents, rewrites links and copies media" do
    fixture = fixture()
    write_fixture_content(fixture)

    {output, status} = build(fixture)
    assert status == 0, output

    generated_doc = read_output(fixture, "guias/instalacao/index.html")
    generated_contribution = read_output(fixture, "biblioteca/contribuir-no-github/index.html")
    generated_library = read_output(fixture, "biblioteca/index.html")
    generated_home = read_output(fixture, "index.html")

    assert generated_doc =~ "<title>Guia de instalação | Tainá</title>"
    assert generated_doc =~ ~s(data-source="guias/instalacao.md")
    assert generated_doc =~ "https://github.com/taina-labs/tekoa/blob/main/guias/instalacao.md"
    assert generated_doc =~ "id=\"seção-um\""
    assert generated_doc =~ ~s(href="#seção-um")
    assert generated_doc =~ ~s(href="/biblioteca/destino/?mode=full#parte")
    assert generated_doc =~ ~s(href="https://example.com/guide")
    assert generated_doc =~ ~s(href="#secao-um")
    assert generated_doc =~ ~s(href="mailto:comunidade@example.com")

    assert generated_doc =~
             "https://github.com/taina-labs/tekoa/blob/main/shared/nao-publicado.md"

    assert generated_doc =~
             ~s(src="/media/tekoa/midia/navegacao-basica.gif" alt="Navegação")

    assert generated_contribution =~
             ~s(src="/media/tekoa/midia/navegacao-basica.gif" alt="Animação mostrando a navegação básica pelo repositório do Tainá no GitHub")

    assert generated_doc =~ ~s(aria-label="Link para o título 'Seção um'")
    assert generated_doc =~ ~s(content="Texto introdutório do Documento sem rota pública.")
    refute generated_doc =~ "Link to heading"
    assert generated_doc =~ "<table>"
    assert generated_doc =~ ~s(type="checkbox")
    assert generated_doc =~ "Este guia está em revisão."

    assert File.regular?(Path.join(fixture.output, "media/tekoa/midia/navegacao-basica.gif"))

    assert generated_library =~ "Catálogo publicado"
    assert generated_library =~ ~s(href="/guias/instalacao/")
    assert generated_library =~ "Guias práticos"
    assert generated_home =~ ~s(href="/biblioteca/destino-editorial/")
    assert generated_home =~ "<title>Início | Tainá</title>"
  end

  test "fails clearly when a source Markdown link is missing" do
    fixture = fixture()
    write_fixture_content(fixture, missing_link?: true)

    {output, status} = build(fixture)
    assert status != 0
    assert output =~ "missing Markdown link target"
    assert output =~ "ausente.md"
  end

  test "fails when a generated page has a missing local link" do
    fixture = fixture()
    write_fixture_content(fixture)
    template = Path.join(fixture.site_root, "templates/page.html.eex")

    File.write!(
      template,
      File.read!(template) <> ~s(<a href="/rota-inexistente/">Inexistente</a>)
    )

    {output, status} = build(fixture)
    assert status != 0
    assert output =~ "missing local link target"
    assert output =~ "/rota-inexistente/"
  end

  test "refuses to clean the repository root" do
    fixture = fixture()
    write_fixture_content(fixture)
    sentinel = Path.join(fixture.root, "keep.txt")
    File.write!(sentinel, "keep")

    {output, status} = build(fixture, fixture.root)
    assert status != 0
    assert output =~ "unsafe output path"
    assert File.read!(sentinel) == "keep"
  end

  test "refuses to clean a directory inside the Tekoa checkout" do
    fixture = fixture()
    write_fixture_content(fixture)
    source = Path.join(fixture.tekoa_root, "guias/instalacao.md")

    {output, status} = build(fixture, Path.join(fixture.tekoa_root, "public"))
    assert status != 0
    assert output =~ "unsafe output path"
    assert File.read!(source) =~ "Guia de instalação"
  end

  defp fixture do
    File.mkdir_p!(@temporary_root)
    root = Path.join(@temporary_root, "site-build-test-#{System.unique_integer([:positive])}")
    site_root = Path.join(root, "site")
    tekoa_root = Path.join(root, "tekoa")
    output = Path.join(root, "output")

    File.mkdir_p!(Path.join(site_root, "templates"))
    File.mkdir_p!(Path.join(site_root, "content"))
    File.mkdir_p!(Path.join(tekoa_root, "guias"))
    File.mkdir_p!(Path.join(tekoa_root, "midia"))
    File.mkdir_p!(Path.join(tekoa_root, "shared"))
    File.mkdir_p!(Path.join(tekoa_root, "aux"))

    on_exit(fn -> File.rm_rf(root) end)

    %{root: root, site_root: site_root, tekoa_root: tekoa_root, output: output}
  end

  defp write_fixture_content(fixture, options \\ []) do
    File.write!(
      Path.join(fixture.site_root, "content/inicio.md"),
      """
      # Início

      [Documento de destino](destino.md)
      """
    )

    File.write!(
      Path.join(fixture.site_root, "content/destino.md"),
      """
      # Destino

      Página editorial.
      """
    )

    File.write!(Path.join(fixture.site_root, "content/estado.md"), "# Estado\n")
    File.write!(Path.join(fixture.site_root, "content/guias.md"), "# Guias\n")
    File.write!(Path.join(fixture.site_root, "content/privacidade.md"), "# Privacidade\n")
    File.write!(Path.join(fixture.site_root, "content/glossario.md"), "# Glossário\n")

    source_link =
      if Keyword.get(options, :missing_link?, false) do
        "[Arquivo ausente](../shared/ausente.md)"
      else
        "[Documento de destino](../shared/a%C3%A7%C3%A3o%20final.md?mode=full#parte)"
      end

    File.write!(
      Path.join(fixture.tekoa_root, "guias/instalacao.md"),
      """
      # Guia de instalação

      Texto introdutório do [Documento sem rota pública](../shared/nao-publicado.md).

      ## Seção um

      Texto.

      ## Seção dois

      Texto.

      ## Seção três

      Texto.

      ### Seção quatro

      Texto.

      ## Seção cinco

      #{source_link}
      [Documento sem rota pública](../shared/nao-publicado.md)

      [Externo](https://example.com/guide)
      [Âncora](#secao-um)
      [E-mail](mailto:comunidade@example.com)

      - [ ] tarefa pendente

      | Campo | Valor |
      | --- | --- |
      | modo | fixture |

      <img src="../midia/navegacao-basica.gif" alt="Navegação" />
      """
    )

    File.write!(
      Path.join(fixture.tekoa_root, "shared/nao-publicado.md"),
      "# Documento sem rota pública\n"
    )

    File.write!(
      Path.join(fixture.tekoa_root, "shared/ação final.md"),
      """
      # Documento de destino

      Conteúdo.
      """
    )

    File.write!(
      Path.join(fixture.tekoa_root, "guias/contribuindo-github.md"),
      "# Contribuir\n\n<img src=\"../midia/navegacao-basica.gif\" />\n"
    )

    File.write!(Path.join(fixture.tekoa_root, "midia/navegacao-basica.gif"), "GIF fixture")
    File.write!(Path.join(fixture.tekoa_root, "aux/history.md"), "# Histórico\n")
    File.write!(Path.join(fixture.tekoa_root, "aux/library.md"), "# Biblioteca\n")
    File.write!(Path.join(fixture.tekoa_root, "aux/architecture.md"), "# Arquitetura\n")
    File.write!(Path.join(fixture.tekoa_root, "aux/roadmap.md"), "# Roadmap\n")

    File.write!(
      Path.join(fixture.site_root, "documents.exs"),
      """
      [
        %{
          source: "guias/instalacao.md",
          url: "/guias/instalacao/",
          section: "Guias",
          notice: "Este guia está em revisão."
        },
        %{
          source: "guias/contribuindo-github.md",
          url: "/biblioteca/contribuir-no-github/",
          section: "Biblioteca"
        },
        %{
          source: "shared/ação final.md",
          url: "/biblioteca/destino/",
          section: "Biblioteca"
        },
        %{
          source: "aux/library.md",
          url: "/biblioteca/",
          section: "Biblioteca"
        },
        %{
          source: "aux/history.md",
          url: "/biblioteca/historico/",
          section: "Biblioteca"
        },
        %{
          source: "aux/architecture.md",
          url: "/biblioteca/arquitetura-atual/",
          section: "Biblioteca"
        },
        %{
          source: "aux/roadmap.md",
          url: "/estado/roadmap/",
          section: "Estado"
        }
      ]
      """
    )

    File.write!(
      Path.join(fixture.site_root, "pages.exs"),
      """
      [
        %{source: "content/inicio.md", url: "/", title: "Início", section: "Início"},
        %{
          source: "content/destino.md",
          url: "/biblioteca/destino-editorial/",
          title: "Destino editorial",
          section: "Biblioteca"
        },
        %{source: "content/estado.md", url: "/estado/", title: "Estado", section: "Estado"},
        %{source: "content/guias.md", url: "/guias/", title: "Guias", section: "Guias"},
        %{
          source: "content/privacidade.md",
          url: "/privacidade/",
          title: "Privacidade",
          section: "Privacidade"
        },
        %{
          source: "content/glossario.md",
          url: "/glossario/",
          title: "Glossário",
          section: "Glossário"
        }
      ]
      """
    )

    File.write!(
      Path.join(fixture.site_root, "templates/page.html.eex"),
      """
      <!doctype html>
      <html lang="pt-BR">
      <head><title><%= @page_title %></title><meta name="description" content="<%= @description %>"></head>
      <body>
        <%= @breadcrumbs_html %>
        <p data-current="<%= @current_path %>" data-section="<%= @section %>" data-document="<%= @document? %>" data-historical="<%= @historical? %>" data-source="<%= @source_path || "" %>" data-source-url="<%= @source_url || "" %>"><%= @title %></p>
        <aside><%= @notice || "" %></aside>
        <%= @toc_html %>
        <article><%= @content %></article>
      </body>
      </html>
      """
    )
  end

  defp build(fixture, output \\ nil) do
    System.cmd(
      "elixir",
      [
        @build_script,
        "--tekoa",
        fixture.tekoa_root,
        "--output",
        output || fixture.output,
        "--site-root",
        fixture.site_root
      ],
      stderr_to_stdout: true
    )
  end

  defp read_output(fixture, path), do: File.read!(Path.join(fixture.output, path))
end