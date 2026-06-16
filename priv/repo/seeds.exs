# Seeds, popula uma instância de desenvolvimento com uma comunidade plausível:
# uma Tekoa, um zelador, dois moradores (mais um convite pendente), pastas e
# alguns arquivos reais (fotos, documento, PDF). Tudo passa pelos contexts
# públicos (Maraca/Ybira), então respeita RLS, cota, detecção de MIME por magic
# bytes e dispara os jobs de thumbnail, exatamente como em produção.
#
#     mix run priv/repo/seeds.exs
#
# Identidade nome-primeiro, sem e-mail (RFC_003, seção 4): convite por link +
# aceite (a pessoa escolhe nome de usuário e senha), login por nome.
#
# Idempotente: se já houver uma Tekoa (RFC 002, D2, uma por instância), não faz
# nada. Use `mix ecto.reset` para recomeçar do zero.

alias Taina.Maraca
alias Taina.Scope
alias Taina.Ybira

if Maraca.bootstrapped?() do
  IO.puts("\nJá existe uma comunidade, seeds ignorados. Use `mix ecto.reset` para recomeçar.\n")
else
  # 256 GB de cota, como nas telas do design.
  quota_bytes = 256 * 1024 * 1024 * 1024
  zelador_password = "semente-da-manha"

  {:ok, %{tekoa: tekoa, ava: zelador}} =
    Maraca.bootstrap(
      %{name: "Quilombo do Café", storage_quota_bytes: quota_bytes},
      %{
        username: "ana",
        display_name: "Ana Oliveira",
        password: zelador_password,
        password_confirmation: zelador_password
      }
    )

  scope = Scope.new(zelador, tekoa)

  # --- Moradores: convite por link + aceite, o fluxo real (sem e-mail) ---

  convidar_e_aceitar = fn username, display_name ->
    {:ok, convidado} = Maraca.invite_user(zelador, tekoa, role: :morador)
    senha = "morador-#{username}-123"

    {:ok, _ava} =
      Maraca.accept_invite(convidado.invite_token, %{
        "username" => username,
        "display_name" => display_name,
        "password" => senha,
        "password_confirmation" => senha
      })
  end

  convidar_e_aceitar.("joao", "João Mendes")
  convidar_e_aceitar.("maria", "Maria Silva")

  # Convite gerado mas ainda não aceito (aparece como pendente nos Moradores).
  {:ok, _pendente} = Maraca.invite_user(zelador, tekoa, role: :morador)

  # --- Pastas ---

  {:ok, documentos} = Ybira.create_folder(scope, %{name: "Documentos"})
  {:ok, fotos} = Ybira.create_folder(scope, %{name: "Fotos da comunidade"})
  {:ok, _videos} = Ybira.create_folder(scope, %{name: "Vídeos"})

  # --- Geração de arquivos reais num diretório temporário ---
  #
  # As fotos são PNGs sólidos (a paleta do grid do design) gerados via libvips,
  # magic bytes válidos, então passam pela allowlist e disparam o worker de
  # thumbnail de verdade.

  tmp = Path.join(System.tmp_dir!(), "taina_seeds_#{System.unique_integer([:positive])}")
  File.mkdir_p!(tmp)

  gera_foto = fn nome, [r, g, b] ->
    caminho = Path.join(tmp, nome)
    img = Image.new!(800, 600, color: [r, g, b])
    Image.write!(img, caminho)
    caminho
  end

  gera_texto = fn nome, conteudo ->
    caminho = Path.join(tmp, nome)
    File.write!(caminho, conteudo)
    caminho
  end

  gera_pdf = fn nome ->
    caminho = Path.join(tmp, nome)
    # PDF mínimo válido, só precisamos dos magic bytes "%PDF" e estrutura básica.
    File.write!(caminho, """
    %PDF-1.4
    1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
    2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
    3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 595 842]>>endobj
    trailer<</Root 1 0 R>>
    %%EOF
    """)

    caminho
  end

  # Paleta de fotos (forest/moon/sky/ember/guara, ver tokens do Penpot).
  paleta = [
    {"festa-junina-01.png", [63, 161, 113]},
    {"festa-junina-02.png", [227, 188, 102]},
    {"assembleia-01.png", [91, 163, 245]},
    {"assembleia-02.png", [226, 103, 74]},
    {"quintal-01.png", [130, 203, 164]},
    {"quintal-02.png", [222, 91, 63]},
    {"horta-01.png", [196, 154, 72]},
    {"horta-02.png", [47, 129, 89]}
  ]

  # Sobe as fotos para a pasta "Fotos da comunidade".
  Enum.each(paleta, fn {nome, rgb} ->
    caminho = gera_foto.(nome, rgb)
    {:ok, _} = Ybira.upload(scope, caminho, filename: nome, folder_id: fotos.id)
  end)

  # Documentos.
  ata =
    gera_texto.(
      "ata-da-assembleia.txt",
      "Ata da assembleia comunitária\n\nPauta: uso do espaço, mutirão de limpeza, festa junina.\n"
    )

  {:ok, _} = Ybira.upload(scope, ata, filename: "Ata da assembleia.txt", folder_id: documentos.id)

  orcamento =
    gera_texto.("orcamento-2025.txt", "Orçamento 2025\n\nReceitas: rifas, doações.\nDespesas: materiais, manutenção.\n")

  {:ok, _} = Ybira.upload(scope, orcamento, filename: "Orçamento 2025.txt", folder_id: documentos.id)

  estatuto = gera_pdf.("estatuto.pdf")
  {:ok, _} = Ybira.upload(scope, estatuto, filename: "Estatuto.pdf", folder_id: documentos.id)

  # Um arquivo na raiz (logo), para a Home ter "recentes" variados.
  logo = gera_foto.("logo-da-radio.png", [255, 217, 163])
  {:ok, _} = Ybira.upload(scope, logo, filename: "Logo da rádio.png")

  File.rm_rf!(tmp)

  IO.puts("""

  Tainá, comunidade de exemplo criada

    Comunidade: #{tekoa.name}
    Zelador:    ana   /  senha: #{zelador_password}
    Moradores:  joao  /  senha: morador-joao-123
                maria /  senha: morador-maria-123
    Pendente:   1 convite de morador gerado, ainda não aceito

    Pastas: Documentos, Fotos da comunidade, Vídeos
    Arquivos: 8 fotos + 3 documentos + 1 logo (thumbnails em segundo plano)

    Entre em http://localhost:4000/login com o nome "ana"
  """)
end
