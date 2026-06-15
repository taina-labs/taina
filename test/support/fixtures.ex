defmodule Taina.Fixtures do
  @moduledoc """
  Fixtures de teste para as entidades centrais.

  Como o modo single-tekoa é imposto por índice único no banco, cada teste
  deve criar no máximo uma Tekoa (o sandbox desfaz tudo ao final).
  """

  alias Taina.Maraca.Ava
  alias Taina.Maraca.Tekoa
  alias Taina.Repo
  alias Taina.Scope

  @gb 1024 * 1024 * 1024

  def tekoa_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "Tekoa Teste #{System.unique_integer([:positive])}",
        storage_quota_bytes: @gb
      })

    %Tekoa{}
    |> Tekoa.changeset(attrs)
    |> Repo.insert!()
  end

  def ava_fixture(%Tekoa{} = tekoa, attrs \\ %{}) do
    n = System.unique_integer([:positive])

    attrs =
      Enum.into(attrs, %{
        username: "ava#{n}",
        email: "ava#{n}@example.com",
        tekoa_id: tekoa.id
      })

    %Ava{}
    |> Ava.changeset(attrs)
    |> Repo.insert!()
  end

  def confirmed_ava_fixture(%Tekoa{} = tekoa, attrs \\ %{}) do
    n = System.unique_integer([:positive])
    password = Map.get(attrs, :password, "senhasegura123")

    base = %{
      username: Map.get(attrs, :username, "ava#{n}"),
      email: Map.get(attrs, :email, "ava#{n}@example.com"),
      role: Map.get(attrs, :role, :member),
      tekoa_id: tekoa.id
    }

    %Ava{}
    |> Ava.changeset(base)
    |> Ava.confirmation_changeset(%{
      username: base.username,
      password: password,
      password_confirmation: password
    })
    |> Repo.insert!()
  end

  def admin_fixture(%Tekoa{} = tekoa, attrs \\ %{}) do
    confirmed_ava_fixture(tekoa, Map.put(attrs, :role, :admin))
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
end
