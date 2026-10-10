defmodule Taina.Maraca.PermissionTest do
  @moduledoc """
  Contrato do `Permission.grant_changeset/2`: `granted_by_id` e `tekoa_id`
  são obrigatórios desde a concessão, a trilha de auditoria nunca nasce pela
  metade (issue #152).

  Sem banco: `grant_changeset/2` é cast/validação pura.
  """
  use ExUnit.Case, async: true

  alias Taina.Maraca.Permission

  @grant_attrs %{
    ava_id: 2,
    resource_type: "ybira_file",
    resource_id: "file_123",
    action: :read,
    granted_by_id: 1,
    tekoa_id: 1
  }

  test "grant_changeset/2 accepts the full grant with the audit fields" do
    changeset = Permission.grant_changeset(%Permission{}, @grant_attrs)

    assert changeset.valid?
    assert changeset.changes.granted_by_id == 1
    assert changeset.changes.tekoa_id == 1
  end

  test "grant_changeset/2 rejects a permission without granted_by_id" do
    changeset = Permission.grant_changeset(%Permission{}, Map.delete(@grant_attrs, :granted_by_id))

    refute changeset.valid?
    assert {:granted_by_id, {"can't be blank", [validation: :required]}} in changeset.errors
  end

  test "grant_changeset/2 rejects a permission without tekoa_id" do
    changeset = Permission.grant_changeset(%Permission{}, Map.delete(@grant_attrs, :tekoa_id))

    refute changeset.valid?
    assert {:tekoa_id, {"can't be blank", [validation: :required]}} in changeset.errors
  end
end
