Mix.install([{:mdex, "== 0.14.1"}])

defmodule TainaSiteBuild do
  @github_tekoa "https://github.com/taina-labs/tekoa/blob/main/"
  @github_site "https://github.com/taina-labs/taina/blob/main/site/"
  @historical_routes [
    "/biblioteca/historico/",
    "/biblioteca/arquitetura-atual/",
    "/estado/roadmap/",
    "/guias/instalacao/",
    "/"
  ]
  @mdex_options [
    extension: [table: true, tasklist: true, autolink: true, header_id_prefix: ""],
    render: [unsafe: true]
  ]
  @attribute_regex ~r/\b(href|src)=(["'])(.*?)\2/s
  @uri_reserved String.to_charlist("-._~!$&'()*+,;=:@/?#")
  @image_alts %{
    {"guias/contribuindo-github.md", "midia/navegacao-basica.gif"} =>
      "Animação mostrando a navegação básica pelo repositório do Tainá no GitHub"
  }
  @static_directories ~w(styles fonts icons js media)
  @static_files ~w(CNAME .nojekyll favicon.ico apple-touch-icon.png og.png version.txt)
  @redirects [
    {"instalar.html", "/guias/instalacao/"},
    {"transparencia.html", "/privacidade/"},
    {"glossario.html", "/glossario/"}
  ]

  def main(arguments) do
    case run(arguments) do
      {:ok, output} ->
        IO.puts("Built static site at #{output}")

      {:error, message} ->
        IO.puts(:stderr, "site build: #{message}")
        System.halt(1)
    end
  end

  def run(arguments) do
    try do
      with {:ok, options} <- parse_options(arguments),
           {:ok, manifests} <- load_manifests(options),
           :ok <- validate_output(options),
           :ok <- build_site(options, manifests) do
        {:ok, options.output}
      end
    rescue
      error -> {:error, Exception.message(error)}
    catch
      kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
    end
  end

  defp parse_options(arguments) do
    {options, positional, invalid} =
      OptionParser.parse(arguments,
        strict: [tekoa: :string, output: :string, site_root: :string, help: :boolean],
        aliases: [h: :help]
      )

    cond do
      Keyword.get(options, :help, false) ->
        IO.puts("Usage: elixir site/build.exs --tekoa PATH [--output PATH] [--site-root PATH]")
        System.halt(0)

      invalid != [] ->
        {:error, "unknown or invalid options: #{inspect(invalid)}"}

      positional != [] ->
        {:error, "unexpected positional arguments: #{Enum.join(positional, " ")}"}

      Keyword.has_key?(options, :output) and options[:output] == "" ->
        {:error, "--output cannot be empty"}

      Keyword.has_key?(options, :site_root) and options[:site_root] == "" ->
        {:error, "--site-root cannot be empty"}

      not is_binary(Keyword.get(options, :tekoa)) or Keyword.get(options, :tekoa) == "" ->
        {:error, "--tekoa is required"}

      true ->
        cwd = File.cwd!()
        site_root = options[:site_root] || Path.dirname(__ENV__.file)
        site_root = Path.expand(site_root, cwd)
        tekoa_root = Path.expand(options[:tekoa], cwd)
        output = options[:output] || Path.join(site_root, "_build")
        output = Path.expand(output, cwd)

        cond do
          not File.dir?(site_root) ->
            {:error, "site root is not a directory: #{site_root}"}

          not File.dir?(tekoa_root) ->
            {:error, "Tekoa path is not a directory: #{tekoa_root}"}

          true ->
            {:ok,
             %{
               site_root: site_root,
               tekoa_root: tekoa_root,
               output: output,
               repo_root: Path.dirname(site_root)
             }}
        end
    end
  end

  defp load_manifests(options) do
    documents_path = Path.join(options.site_root, "documents.exs")
    pages_path = Path.join(options.site_root, "pages.exs")
    template_path = Path.join([options.site_root, "templates", "page.html.eex"])

    cond do
      not File.regular?(documents_path) ->
        {:error, "documents manifest is missing: #{documents_path}"}

      not File.regular?(pages_path) ->
        {:error, "pages manifest is missing: #{pages_path}"}

      not File.regular?(template_path) ->
        {:error, "page template is missing: #{template_path}"}

      true ->
        documents = eval_manifest(documents_path)
        pages = eval_manifest(pages_path)

        with {:ok, documents} <- validate_manifest(documents, options.tekoa_root, :document),
             {:ok, pages} <- validate_manifest(pages, options.site_root, :page),
             :ok <- validate_unique_routes(documents ++ pages) do
          {:ok,
           %{
             documents: documents,
             pages: pages,
             template_path: template_path,
             documents_by_path: Map.new(documents, &{&1.source_abs, &1}),
             pages_by_path: Map.new(pages, &{&1.source_abs, &1})
           }}
        end
    end
  rescue
    error -> {:error, "could not load manifest: #{Exception.message(error)}"}
  end

  defp eval_manifest(path) do
    case Code.eval_file(path) do
      {manifest, _bindings} when is_list(manifest) -> manifest
      _other -> raise "manifest must evaluate to a list: #{path}"
    end
  end

  defp validate_manifest(entries, source_root, kind) when is_list(entries) do
    entries
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {entry, index}, {:ok, acc} ->
      case validate_entry(entry, source_root, kind, index) do
        {:ok, validated} -> {:cont, {:ok, [validated | acc]}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp validate_entry(entry, source_root, kind, index) when is_map(entry) do
    source = Map.get(entry, :source)
    url = Map.get(entry, :url)
    section = Map.get(entry, :section)

    cond do
      not is_binary(source) or source == "" or Path.type(source) == :absolute ->
        {:error, "#{kind} manifest entry #{index} needs a relative source path"}

      not is_binary(url) or not String.starts_with?(url, "/") or
          not String.ends_with?(url, "/") ->
        {:error, "#{kind} manifest entry #{index} needs an absolute site URL ending in /"}

      not is_binary(section) ->
        {:error, "#{kind} manifest entry #{index} needs a section"}

      true ->
        source_abs = Path.expand(source, source_root)

        cond do
          not path_within?(source_abs, source_root) ->
            {:error, "#{kind} source escapes its root: #{source}"}

          not File.regular?(source_abs) ->
            {:error, "missing #{kind} source: #{source_abs}"}

          Path.extname(source_abs) |> String.downcase() != ".md" ->
            {:error, "#{kind} source is not a Markdown file: #{source}"}

          Map.get(entry, :historical, false) not in [true, false] ->
            {:error, "historical must be a boolean for #{source}"}

          true ->
            {:ok,
             entry
             |> Map.put(:source_abs, source_abs)
             |> Map.put(:source_root, source_root)
             |> Map.put(:kind, kind)
             |> Map.put(:historical, Map.get(entry, :historical, false))}
        end
    end
  end

  defp validate_entry(_entry, _source_root, kind, index),
    do: {:error, "#{kind} manifest entry #{index} must be a map"}

  defp validate_unique_routes(entries) do
    duplicates =
      entries
      |> Enum.group_by(& &1.url)
      |> Enum.filter(fn {_url, matches} -> length(matches) > 1 end)
      |> Enum.map(&elem(&1, 0))

    if duplicates == [],
      do: :ok,
      else: {:error, "manifest routes must be unique: #{Enum.join(duplicates, ", ")}"}
  end

  defp validate_output(options) do
    output = options.output
    protected = ["/", options.repo_root, options.site_root, options.tekoa_root]

    output_symlink? =
      case File.lstat(output) do
        {:ok, %{type: :symlink}} -> true
        _ -> false
      end

    cond do
      output == "" ->
        {:error, "output path cannot be empty"}

      output_symlink? ->
        {:error, "refusing to clean a symlink output path: #{output}"}

      Enum.any?(protected, &path_within?(&1, output)) or
          path_within?(output, options.tekoa_root) ->
        {:error, "refusing unsafe output path: #{output}"}

      true ->
        :ok
    end
  end

  defp path_within?(path, root) do
    path = Path.expand(path)
    root = Path.expand(root)
    path == root or String.starts_with?(path, String.trim_trailing(root, "/") <> "/")
  end

  defp build_site(options, manifests) do
    with :ok <- clean_output(options.output),
         :ok <- copy_static_assets(options.site_root, options.output),
         :ok <- render_entries(options, manifests),
         :ok <- write_redirects(options.output),
         :ok <- validate_generated_site(options, manifests) do
      :ok
    end
  end

  defp clean_output(output) do
    case File.rm_rf(output) do
      {:ok, _removed} -> File.mkdir_p(output)
      {:error, path, reason} -> {:error, "could not clean #{path}: #{:file.format_error(reason)}"}
    end
  end

  defp copy_static_assets(site_root, output) do
    Enum.each(@static_directories, fn directory ->
      copy_if_present(Path.join(site_root, directory), Path.join(output, directory))
    end)

    Enum.each(@static_files, fn filename ->
      copy_if_present(Path.join(site_root, filename), Path.join(output, filename))
    end)

    :ok
  rescue
    error -> {:error, "could not copy static assets: #{Exception.message(error)}"}
  end

  defp copy_if_present(source, destination) do
    if File.dir?(source) or File.regular?(source) do
      case File.cp_r(source, destination) do
        {:ok, _copied} ->
          :ok

        {:error, source_path, reason} ->
          raise "could not copy #{source_path}: #{:file.format_error(reason)}"
      end
    end
  end

  defp render_entries(options, manifests) do
    entries = manifests.pages ++ manifests.documents

    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case render_entry(entry, options, manifests) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp render_entry(entry, options, manifests) do
    markdown = File.read!(entry.source_abs)
    document = MDEx.parse_document!(markdown, @mdex_options)
    html = MDEx.to_html!(document, @mdex_options)

    title =
      Map.get(entry, :title) || first_heading(document) || Path.basename(entry.source, ".md")

    description = Map.get(entry, :description) || derive_description(document, title)

    html =
      html
      |> localize_heading_labels()
      |> ensure_image_alts(entry)
      |> append_library_catalog(entry, manifests)
      |> rewrite_html_links(entry, options, manifests)

    toc_html = build_toc(document, entry.kind == :document)

    source_url =
      if entry.kind == :document do
        @github_tekoa <> encode_path(entry.source)
      end

    assigns = [
      page_title: "#{escape_html(title)} | Tainá",
      title: title,
      description: escape_attribute(description, "\""),
      canonical_url: entry.url,
      current_path: entry.url,
      section: entry.section,
      content: html,
      document?: entry.kind == :document,
      source_path: if(entry.kind == :document, do: entry.source),
      source_url: source_url,
      notice: Map.get(entry, :notice),
      historical?: entry.historical,
      toc_html: toc_html,
      breadcrumbs_html: breadcrumbs(entry, title)
    ]

    output_path = Path.join([options.output, String.trim_leading(entry.url, "/"), "index.html"])

    with :ok <- File.mkdir_p(Path.dirname(output_path)),
         rendered <- EEx.eval_file(manifests.template_path, assigns: Map.new(assigns)),
         :ok <- File.write(output_path, rendered) do
      :ok
    end
  rescue
    error ->
      {:error, "could not render #{entry.source}: #{Exception.message(error)}"}
  end

  defp first_heading(document) do
    Enum.find_value(document.nodes, fn
      %MDEx.Heading{level: 1} = heading -> plain_text(heading)
      _node -> nil
    end)
  end

  defp derive_description(document, fallback) do
    description =
      Enum.find_value(document.nodes, fn
        %MDEx.Paragraph{} = paragraph -> plain_text(paragraph)
        _node -> nil
      end)

    case description do
      nil -> fallback
      text -> text |> String.replace(~r/\s+/u, " ") |> String.trim() |> truncate_description()
    end
  end

  defp truncate_description(text) do
    if String.length(text) > 180 do
      text
      |> String.slice(0, 180)
      |> String.replace(~r/\s+\S*$/u, "")
    else
      text
    end
  end

  defp plain_text(node) when is_map(node) do
    literal =
      case Map.get(node, :literal) do
        text when is_binary(text) -> Regex.replace(~r/<[^>]*>/u, text, "")
        _ -> ""
      end

    children =
      node
      |> Map.get(:nodes, [])
      |> Enum.map_join(" ", &plain_text/1)

    (literal <> " " <> children)
    |> html_unescape()
    |> String.replace(~r/\s+/u, " ")
    |> String.replace(~r/\s+([,.;:!?\)\]])/u, "\\1")
    |> String.replace(~r/([\(\[])\s+/u, "\\1")
    |> String.trim()
  end

  defp plain_text(_node), do: ""

  defp localize_heading_labels(html) do
    String.replace(html, ~s(aria-label="Link to heading ), ~s(aria-label="Link para o título ))
  end

  defp ensure_image_alts(html, entry) do
    Regex.replace(~r/<img\b([^>]*)>/i, html, fn whole, attributes ->
      if Regex.match?(~r/\balt\s*=/i, attributes) do
        whole
      else
        relative_media = Path.relative_to(entry.source_abs, entry.source_root)
        source_path = attributes |> image_source() |> source_relative_path(entry)
        alt = missing_image_alt(relative_media, source_path)
        attributes = String.trim_trailing(attributes, "/") |> String.trim_trailing()
        "<img#{attributes} alt=\"#{escape_attribute(alt, "\"")}\" />"
      end
    end)
  end

  defp image_source(attributes) do
    case Regex.run(~r/\bsrc=(["'])(.*?)\1/i, attributes) do
      [_, _quote, source] -> source
      nil -> ""
    end
  end

  defp source_relative_path("", _entry), do: ""

  defp source_relative_path(source, entry) do
    source
    |> URI.parse()
    |> Map.get(:path)
    |> Kernel.||("")
    |> URI.decode()
    |> Path.expand(Path.dirname(entry.source_abs))
    |> Path.relative_to(entry.source_root)
  end

  defp missing_image_alt(source, media_path) do
    Map.get(@image_alts, {source, media_path}, "Imagem do documento #{source}")
  end

  defp build_toc(document, true) do
    headings =
      Enum.filter(document.nodes, fn
        %MDEx.Heading{level: level} when level in [2, 3] -> true
        _node -> false
      end)

    if length(headings) < 5 do
      ""
    else
      {items, _ids} =
        Enum.map_reduce(headings, %{}, fn heading, seen ->
          label = plain_text(heading)
          slug = MDEx.anchorize(label)
          count = Map.get(seen, slug, 0)
          id = if count == 0, do: slug, else: "#{slug}-#{count}"
          seen = Map.put(seen, slug, count + 1)

          {~s(<li class="page-toc__item page-toc__item--level-#{heading.level}"><a href="##{escape_html(id)}">#{escape_html(label)}</a></li>),
           seen}
        end)

      "<ul>#{Enum.join(items, "\n")}</ul>"
    end
  end

  defp build_toc(_document, _is_document), do: ""

  defp append_library_catalog(html, %{kind: :document, url: "/biblioteca/"} = entry, manifests) do
    documents = Enum.reject(manifests.documents, &(&1.source_abs == entry.source_abs))

    groups = [
      {"Guias práticos",
       fn document -> document.section == "Guias" and not document.historical end},
      {"Estado e planejamento", fn document -> document.section == "Estado" end},
      {"Documentação do projeto",
       fn document ->
         document.section == "Biblioteca" and not document.historical
       end},
      {"Arquivo histórico", fn document -> document.historical end}
    ]

    sections =
      groups
      |> Enum.map(fn {title, predicate} -> {title, Enum.filter(documents, predicate)} end)
      |> Enum.reject(fn {_title, documents} -> documents == [] end)
      |> Enum.map_join("\n", &library_catalog_section/1)

    html <>
      ~s(<hr /><section class="library-catalog" aria-labelledby="catalogo-publicado">) <>
      ~s(<h2 id="catalogo-publicado">Catálogo publicado</h2>) <>
      "<p>Todos os documentos canônicos do Tekoá disponíveis neste portal.</p>" <>
      sections <> "</section>"
  end

  defp append_library_catalog(html, _entry, _manifests), do: html

  defp library_catalog_section({title, documents}) do
    items =
      documents
      |> Enum.map(fn document -> {document_title(document), document.url} end)
      |> Enum.sort_by(fn {title, _url} -> String.downcase(title) end)
      |> Enum.map_join("\n", fn {title, url} ->
        ~s(<li><a href="#{escape_attribute(url, "\"")}">#{escape_html(title)}</a></li>)
      end)

    "<h3>#{escape_html(title)}</h3><ul>#{items}</ul>"
  end

  defp document_title(entry) do
    Map.get(entry, :title) ||
      entry.source_abs
      |> File.read!()
      |> MDEx.parse_document!(@mdex_options)
      |> first_heading() ||
      Path.basename(entry.source, ".md")
  end

  defp breadcrumbs(entry, title) do
    section_url =
      case entry.section do
        "Guias" -> "/guias/"
        "Estado" -> "/estado/"
        "Biblioteca" -> "/biblioteca/"
        _section -> nil
      end

    section =
      if section_url && section_url != entry.url do
        ~s(<li><a href="#{section_url}">#{escape_html(entry.section)}</a></li>)
      else
        ""
      end

    ~s(<nav class="breadcrumbs" aria-label="Navegação estrutural"><ol><li><a href="/">Início</a></li>#{section}<li aria-current="page">#{escape_html(title)}</li></ol></nav>)
  end

  defp rewrite_html_links(html, entry, options, manifests) do
    Regex.replace(@attribute_regex, html, fn _whole, attribute, quote, value ->
      uri = value |> html_unescape() |> rewrite_uri(attribute, entry, options, manifests)
      "#{attribute}=#{quote}#{escape_attribute(uri, quote)}#{quote}"
    end)
  end

  defp rewrite_uri(value, attribute, entry, options, manifests) do
    uri = URI.parse(value)
    path = uri.path || ""

    cond do
      uri.scheme != nil or uri.host != nil ->
        value

      String.starts_with?(path, "/") or path == "" ->
        value

      true ->
        resolved = resolve_source_path(path, entry)
        relative = Path.relative_to(resolved, entry.source_root)

        cond do
          String.downcase(Path.extname(path)) == ".md" ->
            rewrite_markdown_link(uri, resolved, relative, entry, manifests)

          attribute == "src" ->
            rewrite_media_source(resolved, relative, entry, options)

          File.regular?(resolved) ->
            github_file_url(resolved, relative, entry, uri)

          true ->
            raise "missing local link target #{path} in #{entry.source}"
        end
    end
  rescue
    error in [ArgumentError] ->
      raise "invalid local URL #{inspect(value)} in #{entry.source}: #{Exception.message(error)}"
  end

  defp resolve_source_path(uri_path, entry) do
    decoded_path = URI.decode(uri_path)
    source_path = Path.expand(decoded_path, Path.dirname(entry.source_abs))

    unless path_within?(source_path, entry.source_root) do
      raise "local link escapes source root in #{entry.source}: #{uri_path}"
    end

    source_path
  end

  defp rewrite_markdown_link(uri, resolved, relative, entry, manifests) do
    unless File.regular?(resolved) do
      raise "missing Markdown link target #{relative} in #{entry.source}"
    end

    known =
      case entry.kind do
        :document -> Map.get(manifests.documents_by_path, resolved)
        :page -> Map.get(manifests.pages_by_path, resolved)
      end

    case known do
      %{url: url} -> url <> uri_suffix(uri)
      nil -> github_file_url(resolved, relative, entry, uri)
    end
  end

  defp rewrite_media_source(resolved, relative, entry, options) do
    unless File.regular?(resolved) do
      raise "missing media source #{relative} in #{entry.source}"
    end

    prefix = if entry.kind == :document, do: "tekoa", else: "pages"
    media_relative = Path.join([prefix, relative])
    destination = Path.join([options.output, "media", media_relative])

    with :ok <- File.mkdir_p(Path.dirname(destination)),
         :ok <- File.cp(resolved, destination) do
      "/media/#{encode_path(media_relative)}"
    else
      {:error, reason} -> raise "could not copy media #{relative}: #{:file.format_error(reason)}"
    end
  end

  defp github_file_url(_resolved, relative, %{kind: :document}, uri),
    do: @github_tekoa <> encode_path(relative) <> uri_suffix(uri)

  defp github_file_url(_resolved, relative, %{kind: :page}, uri),
    do: @github_site <> encode_path(relative) <> uri_suffix(uri)

  defp uri_suffix(uri) do
    query = if uri.query, do: "?" <> encode_component(uri.query), else: ""
    fragment = if uri.fragment, do: "#" <> encode_component(uri.fragment), else: ""
    query <> fragment
  end

  defp encode_path(path) do
    path
    |> String.split("/", trim: false)
    |> Enum.map_join("/", fn segment -> URI.encode(segment, &URI.char_unreserved?/1) end)
  end

  defp encode_component(value) do
    URI.encode(value, fn char -> URI.char_unreserved?(char) or char in @uri_reserved end)
  end

  defp html_unescape(value) do
    value
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&#x27;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
  end

  defp escape_attribute(value, "\"") do
    value |> String.replace("&", "&amp;") |> String.replace("\"", "&quot;")
  end

  defp escape_attribute(value, "'") do
    value |> String.replace("&", "&amp;") |> String.replace("'", "&#39;")
  end

  defp escape_html(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp write_redirects(output) do
    Enum.each(@redirects, fn {filename, target} ->
      html = """
      <!doctype html>
      <html lang="pt-BR">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="refresh" content="0; url=#{target}">
        <link rel="canonical" href="#{target}">
        <title>Página movida</title>
      </head>
      <body>
        <p>Esta página mudou. <a href="#{target}">Acesse o novo endereço</a>.</p>
      </body>
      </html>
      """

      File.write!(Path.join(output, filename), html)
    end)

    :ok
  rescue
    error -> {:error, "could not write redirects: #{Exception.message(error)}"}
  end

  defp validate_generated_site(options, manifests) do
    required = Enum.map(@historical_routes, &route_index(options.output, &1))
    document_routes = Enum.map(manifests.documents, &route_index(options.output, &1.url))
    page_routes = Enum.map(manifests.pages, &route_index(options.output, &1.url))

    missing_routes =
      (required ++ document_routes ++ page_routes)
      |> Enum.uniq()
      |> Enum.reject(&File.regular?/1)

    cond do
      missing_routes != [] ->
        {:error, "required route was not generated: #{Enum.join(missing_routes, ", ")}"}

      true ->
        validate_all_local_links(options.output)
    end
  end

  defp route_index(output, route),
    do: Path.join([output, String.trim_leading(route, "/"), "index.html"])

  defp validate_all_local_links(output) do
    output
    |> Path.join("**/*.html")
    |> Path.wildcard()
    |> Enum.reduce_while(:ok, fn html_path, :ok ->
      case validate_file_links(html_path, output) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_file_links(html_path, output) do
    html = File.read!(html_path)

    links =
      Regex.scan(@attribute_regex, html, capture: :all_but_first)
      |> Enum.map(fn [attribute, _quote, value] -> {attribute, html_unescape(value)} end)

    Enum.reduce_while(links, :ok, fn {_attribute, value}, :ok ->
      case local_file_target(value, html_path, output) do
        :ignore ->
          {:cont, :ok}

        target ->
          if File.regular?(target) do
            {:cont, :ok}
          else
            {:halt,
             {:error,
              "missing local link target #{value} in #{Path.relative_to(html_path, output)}"}}
          end
      end
    end)
  rescue
    error -> {:error, "could not validate #{html_path}: #{Exception.message(error)}"}
  end

  defp local_file_target(value, html_path, output) do
    uri = URI.parse(value)
    path = uri.path || ""

    cond do
      uri.scheme != nil or uri.host != nil ->
        :ignore

      path == "" ->
        :ignore

      String.starts_with?(path, "/") ->
        generated_target(output, URI.decode(path))

      true ->
        generated_target(Path.dirname(html_path), URI.decode(path))
    end
  end

  defp generated_target(root, path) do
    target = Path.expand(String.trim_leading(path, "/"), root)

    if path_within?(target, root) do
      cond do
        File.dir?(target) -> Path.join(target, "index.html")
        Path.extname(target) == "" -> Path.join(target, "index.html")
        true -> target
      end
    else
      Path.join(target, "index.html")
    end
  end
end

TainaSiteBuild.main(System.argv())