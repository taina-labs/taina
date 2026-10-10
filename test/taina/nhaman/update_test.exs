defmodule Taina.Nhaman.UpdateTest do
  @moduledoc """
  Verificação de atualização (tela "Saúde da comunidade").

  Cobre as partes puras (normalização, comparação) e o estado soberano: sem
  ninguém ligar `TAINA_UPDATE_CHECK`, a caixa não faz pergunta nenhuma, e o
  status diz isso como estado, sem fingir "atualizado". O GET em si não é
  testado: é opt-in, opcional e degradável, a caixa não sai conversando com a
  internet por causa de teste.
  """

  use ExUnit.Case, async: true

  alias Taina.Nhaman.Update

  describe "normalize_version/1" do
    test "tira o v da tag de release" do
      assert Update.normalize_version("v0.2.0") == "0.2.0"
    end

    test "mantém a versão nua e aparada" do
      assert Update.normalize_version(" 0.2.0 ") == "0.2.0"
    end
  end

  describe "compare/2" do
    test "igual e maior que a publicada: atualizado" do
      assert Update.compare("0.2.0", "0.2.0") == :up_to_date
      assert Update.compare("0.3.0", "0.2.0") == :up_to_date
    end

    test "menor que a publicada: existe mais nova" do
      assert Update.compare("0.1.0", "0.2.0") == {:update_available, "0.2.0"}
    end

    test "versão que não é Version não inventa resposta" do
      assert Update.compare("x", "0.2.0") == :unknown
      assert Update.compare("0.1.0", "desconhecida") == :unknown
    end
  end

  describe "status/0" do
    test "desligada por padrão (soberana): a caixa não pergunta nada para ninguém" do
      refute Update.enabled?()

      assert %{result: :check_off, running: running} = Update.status(releases_url: "http://127.0.0.1:1/ninguem")
      assert {:ok, %Version{}} = Version.parse(running)
    end
  end
end
