defmodule TainaWeb.MuralTextTest do
  use ExUnit.Case, async: true

  alias TainaWeb.MuralText
  alias Ypy.Mural.Entry

  test "backup events use system language when the payload has no actor" do
    assert MuralText.sentence(%Entry{tipo: "backup_scheduled", payload: %{}}, %{}) ==
             "O sistema agendou um backup."

    assert MuralText.sentence(%Entry{tipo: "backup_succeeded", payload: %{}}, %{}) ==
             "O sistema concluiu um backup."

    assert MuralText.sentence(%Entry{tipo: "backup_failed", payload: %{}}, %{}) ==
             "O sistema não conseguiu concluir um backup."
  end
end
