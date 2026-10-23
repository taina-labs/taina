defmodule Ypy.WireTest do
  use ExUnit.Case, async: true

  alias Ypy.Tid
  alias Ypy.Wire
  alias Ypy.Wire.Ava
  alias Ypy.Wire.Errors
  alias Ypy.Wire.File
  alias Ypy.Wire.Mural
  alias Ypy.Ybira.Folder

  @agora 1_700_000_000_000_000

  # O vocabulario completo (RFC_005 secao 6 mais os motivos dos contextos do
  # kernel), motivo a motivo com o status da tabela.
  @motivos [
    {:not_authenticated, 401},
    {:invalid_credentials, 401},
    {:invalid_token, 401},
    {:account_deactivated, 403},
    {:forbidden, 403},
    {:unauthorized, 403},
    {:not_zelador, 403},
    {:not_owner, 403},
    {:not_authorized, 403},
    {:not_found, 404},
    {:no_folder, 404},
    {:last_zelador, 409},
    {:not_pending, 409},
    {:invalid_status, 409},
    {:already_has_access, 409},
    {:already_readable, 409},
    {:already_bootstrapped, 409},
    {:not_bootstrapped, 409},
    {:circular_reference, 409},
    {:storage_quota_exceeded, 409},
    {:rkey_conflict, 409},
    {:chain_conflict, 409},
    {:expirada, 409},
    {:already_executed, 409},
    {:cannot_request_own, 422},
    {:cross_tekoa_owner, 422},
    {:cross_tekoa, 422},
    {:invalid_action, 422},
    {:mime_not_allowed, 422},
    {:missing_file, 422},
    {:invalid_tipo, 422},
    {:payload_invalido, 422},
    {:rate_limited, 429},
    {:envelope_invalido, 500},
    {:missing_mime, 500},
    {:missing_fecha_em, 500},
    {:bad_seq, 500},
    {:bad_link, 500},
    {:bad_entry, 500},
    {:bad_signature, 500}
  ]

  test "o envelope de paginacao leva itens e cursor" do
    assert Wire.page([%{"a" => 1}], "cursor") == %{
             "items" => [%{"a" => 1}],
             "next_cursor" => "cursor"
           }

    assert Wire.page([], nil) == %{"items" => [], "next_cursor" => nil}
  end

  test "o envelope do conteudo de pasta leva pastas, itens e cursor" do
    assert Wire.folder_page([%{"f" => 1}], [%{"a" => 1}], nil) == %{
             "folders" => [%{"f" => 1}],
             "items" => [%{"a" => 1}],
             "next_cursor" => nil
           }
  end

  test "o mapa do ava leva a palavra do dominio no papel e momentos em ISO-8601" do
    assert Ava.json(ava()) == %{
             "public_id" => "Ab3_xYz9_-Q1",
             "username" => "ana",
             "display_name" => "Ana",
             "papel" => "zelador",
             "activated_at" => "2026-10-12T12:00:00Z",
             "deactivated_at" => nil,
             "created_at" => "2026-10-12T11:00:00Z"
           }
  end

  test "o mapa do arquivo leva os enderecos do mundo CBOR e o sha256" do
    assert File.json(file()) == %{
             "rkey" => rkey(),
             "cid" => cid(),
             "blob_cid" => cid(),
             "sha256" => hash(),
             "name" => "foto.jpg",
             "mime" => "image/jpeg",
             "size" => 1024,
             "zona" => "casa",
             "folder" => folder_rkey(),
             "dono" => "Ab3_xYz9_-Q1",
             "deleted_at" => nil,
             "created_at" => "2026-10-12T12:00:00Z",
             "updated_at" => "2026-10-12T12:00:00Z"
           }
  end

  test "o dono com preload sai pelo public_id, e sem preload sai null" do
    assert File.json(file())["dono"] == "Ab3_xYz9_-Q1"
    assert File.json(%{file() | dono: nil})["dono"] == nil
    assert File.json(%{file() | dono: %Ecto.Association.NotLoaded{}})["dono"] == nil
  end

  test "a pasta pai sem preload sai null, e a lixeira sai como deleted_at" do
    trashed = %{file() | folder: nil, apagado_em: ~U[2026-10-12 13:00:00Z]}

    map = File.json(trashed)

    assert map["folder"] == nil
    assert map["deleted_at"] == "2026-10-12T13:00:00Z"
  end

  test "o mapa da pasta leva a pasta de cima pelo rkey e a zona" do
    folder = %Folder{
      rkey: folder_rkey(),
      cid: cid(),
      nome: "Fotos",
      zona: :praca,
      dono: ava(),
      parent: %Folder{rkey: rkey()},
      inserted_at: ~U[2026-10-12 12:00:00Z],
      updated_at: ~U[2026-10-12 12:00:00Z]
    }

    assert File.json(folder) == %{
             "rkey" => folder_rkey(),
             "cid" => cid(),
             "name" => "Fotos",
             "zona" => "praca",
             "folder" => rkey(),
             "dono" => "Ab3_xYz9_-Q1",
             "deleted_at" => nil,
             "created_at" => "2026-10-12T12:00:00Z",
             "updated_at" => "2026-10-12T12:00:00Z"
           }

    assert File.json(%{folder | dono: nil})["dono"] == nil
  end

  test "o mapa da entrada do mural leva as coordenadas da cadeia e o payload" do
    payload = %{"actor" => "Ab3_xYz9_-Q1", "collection" => "ypy.file.v0", "rkey" => rkey()}

    entry = %Ypy.Mural.Entry{
      seq: 7,
      prev: nil,
      tipo: "put",
      payload: payload,
      signature: :crypto.strong_rand_bytes(64),
      cid: cid(),
      inserted_at: ~U[2026-10-12 12:00:00Z]
    }

    assert Mural.json(entry) == %{
             "seq" => 7,
             "tipo" => "put",
             "payload" => payload,
             "cid" => cid(),
             "prev" => nil,
             "created_at" => "2026-10-12T12:00:00Z"
           }
  end

  test "todo motivo do vocabulario leva o status da tabela e o proprio atomo como code" do
    Enum.each(@motivos, fn {motivo, status} ->
      assert Errors.resolve(motivo) == {status, Atom.to_string(motivo)}
      assert Errors.status(motivo) == status
    end)
  end

  test "changeset e validation_failed e motivo sem mapeamento e internal_error" do
    assert Errors.resolve(%Ecto.Changeset{}) == {422, "validation_failed"}
    assert Errors.resolve(:motivo_nenhum) == {500, "internal_error"}
    assert Errors.resolve("lixo") == {500, "internal_error"}
    assert Errors.status(:motivo_nenhum) == nil
  end

  defp ava do
    %Ypy.Maraca.Ava{
      id: 1,
      username: "ana",
      display_name: "Ana",
      papel: :zelador,
      public_id: "Ab3_xYz9_-Q1",
      activated_at: ~U[2026-10-12 12:00:00Z],
      inserted_at: ~U[2026-10-12 11:00:00Z]
    }
  end

  defp file do
    %Ypy.Ybira.File{
      id: 3,
      rkey: rkey(),
      cid: cid(),
      blob_cid: cid(),
      nome: "foto.jpg",
      mime: "image/jpeg",
      tamanho: 1024,
      hash: hash(),
      zona: :casa,
      dono: ava(),
      folder: %Folder{rkey: folder_rkey()},
      inserted_at: ~U[2026-10-12 12:00:00Z],
      updated_at: ~U[2026-10-12 12:00:00Z]
    }
  end

  defp rkey do
    {rkey, _} = Tid.next(0, @agora, 0)
    rkey
  end

  defp folder_rkey do
    {rkey, _} = Tid.next(0, @agora - 1, 0)
    rkey
  end

  defp cid, do: "amostra" |> Ypy.Cid.from_data() |> Ypy.Cid.to_string()

  defp hash, do: String.duplicate("0f", 32)
end
