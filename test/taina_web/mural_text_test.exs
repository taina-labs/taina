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

  test "unlimited quota uses the whole-disk sentence and resolves the actor" do
    event = %Entry{tipo: "quota_changed", payload: %{"actor" => "ava-1", "to" => nil}}

    assert MuralText.sentence(event, %{"ava-1" => "Carla"}) ==
             "Carla liberou o disco inteiro para a comunidade."
  end

  test "quota transition formats both limits" do
    event = %Entry{
      tipo: "quota_changed",
      payload: %{"actor" => "ava-1", "from" => 50 * 1_073_741_824, "to" => 100 * 1_073_741_824}
    }

    assert MuralText.sentence(event, %{"ava-1" => "Carla"}) ==
             "Carla mudou o limite de armazenamento de 50 GB para 100 GB."
  end
end
