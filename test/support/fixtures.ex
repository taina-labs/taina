defmodule Taina.Fixtures do
  @moduledoc """
  Fixtures de teste para as entidades centrais.

  Como o modo single-tekoa é imposto por índice único no banco, cada teste
  deve criar no máximo uma Tekoa (o sandbox desfaz tudo ao final). A Tekoa
  nasce com a chave que assina a cadeia (`Taina.Keys.mint/2`): uploads e atos
  sociais do kernel assinam.
  """

  alias Taina.Keys
  alias Taina.Repo
  alias Taina.Scope
  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Tekoa

  @gb 1024 * 1024 * 1024

  def tekoa_fixture(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    attrs =
      Enum.into(attrs, %{
        name: "Tekoa Teste #{n}",
        domain: "tekoa-#{String.downcase(Integer.to_string(n, 36))}.test",
        storage_quota_bytes: @gb
      })

    {:ok, tekoa} =
      Repo.insert(Tekoa.changeset(%Tekoa{}, attrs))

    :ok = Keys.mint(Repo, tekoa.id)

    Repo.reload!(tekoa, skip_tekoa_id: true)
  end

  # Convite pendente: tem nome mas ainda sem senha (conta não ativada).
  def ava_fixture(%Tekoa{} = tekoa, attrs \\ %{}) do
    n = System.unique_integer([:positive])

    attrs =
      Enum.into(attrs, %{
        username: "ava#{n}",
        tekoa_id: tekoa.id
      })

    %Ava{tekoa_id: tekoa.id}
    |> Ava.changeset(Map.take(attrs, [:username, :display_name, :papel]))
    |> Repo.insert!()
  end

  # Conta ativa: nome de usuário + senha definidos (convite aceito). O papel
  # não entra pelo accept_changeset do kernel (ele casta identidade e senha
  # apenas): vai como change programático, como no zelador do bootstrap.
  def active_ava_fixture(%Tekoa{} = tekoa, attrs \\ %{}) do
    n = System.unique_integer([:positive])

    papel = Map.get(attrs, :papel, :morador)

    base = %{
      username: Map.get(attrs, :username, "ava#{n}"),
      display_name: Map.get(attrs, :display_name),
      password: Map.get(attrs, :password, "senhasegura123")
    }

    %Ava{tekoa_id: tekoa.id}
    |> Ava.accept_changeset(base)
    |> Ecto.Changeset.change(papel: papel)
    |> Repo.insert!()
  end

  def zelador_fixture(%Tekoa{} = tekoa, attrs \\ %{}) do
    active_ava_fixture(tekoa, Map.put(attrs, :papel, :zelador))
  end

  def scope_fixture(attrs \\ %{}) do
    tekoa = tekoa_fixture(attrs)
    ava = ava_fixture(tekoa)
    Scope.new(ava, tekoa)
  end

  def tmp_upload_fixture(contents \\ "conteúdo de teste", filename \\ "doc.txt") do
    dir = Path.join(System.tmp_dir!(), "taina_fixture_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, filename)
    File.write!(path, contents)
    path
  end

  @doc """
  Grava uma imagem JPEG de verdade num caminho temporário (via libvips), para
  exercitar o pipeline de renditions do Ybira/Jaci. Sem EXIF, `taken_at` cai no
  fallback de upload, como num arquivo sem metadados de câmera.
  """
  def tmp_image_fixture(opts \\ []) do
    width = Keyword.get(opts, :width, 32)
    height = Keyword.get(opts, :height, 24)
    filename = Keyword.get(opts, :filename, "img.jpg")

    dir = Path.join(System.tmp_dir!(), "taina_fixture_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, filename)

    {:ok, image} = Image.new(width, height, color: [255, 0, 0])
    {:ok, _} = Image.write(image, path)
    path
  end

  @doc """
  Grava um arquivo com os magic bytes de um contêiner ISO-BMFF `ftyp/mp42`, o
  bastante para o `MimeDetector` classificar como `video/mp4`. Sem faixas reais,
  só exercita a allowlist e o filtro image/video do Jaci/Ybira.
  """
  def tmp_video_fixture(filename \\ "v.mp4") do
    tmp_upload_fixture(<<0, 0, 0, 0x18, "ftyp", "mp42", 0, 0, 0, 0>>, filename)
  end
end
