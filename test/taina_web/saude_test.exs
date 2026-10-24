defmodule TainaWeb.SaudeTest do
  use ExUnit.Case, async: true

  alias TainaWeb.Saude

  describe "summary_line/1" do
    test ":ok quando o disco tem espaco e o backup terminou bem" do
      resumo =
        Saude.summary_line(%{
          storage: %{used_bytes: 50, quota_bytes: 100},
          backup: {:ok, %{at: DateTime.utc_now(), bytes: 100}}
        })

      assert resumo == %{state: :ok, line: "Backup em dia"}
    end

    test ":attention com \"Último backup falhou\" mesmo sem cota definida" do
      resumo =
        Saude.summary_line(%{
          storage: %{used_bytes: 9_000, quota_bytes: nil},
          backup: {:error, :unreadable}
        })

      # Sem limite em bytes o disco por si so nunca chama atencao; o backup
      # e quem fala. Backup ilegivel fala "falhou".
      assert resumo == %{state: :attention, line: "Último backup falhou"}
    end

    test ":attention com \"Nenhum backup ainda\" quando nunca houve backup" do
      # Caixa nova (`:none`/`:no_dir`): atencao pelo estado, mas a frase e
      # honesta; "Último backup falhou" seria mentira.
      for reason <- [:none, :no_dir] do
        resumo =
          Saude.summary_line(%{
            storage: %{used_bytes: 10, quota_bytes: 100},
            backup: {:error, reason}
          })

        assert resumo == %{state: :attention, line: "Nenhum backup ainda"}
      end
    end

    test ":attention com \"Disco quase cheio\" em 90% da cota" do
      resumo =
        Saude.summary_line(%{
          storage: %{used_bytes: 90, quota_bytes: 100},
          backup: {:ok, %{at: DateTime.utc_now(), bytes: 100}}
        })

      # O disco fala antes do backup, mesmo com backup em dia.
      assert resumo == %{state: :attention, line: "Disco quase cheio"}
    end

    test ":attention com \"Último backup falhou\" em {:error, _}" do
      resumo =
        Saude.summary_line(%{
          storage: %{used_bytes: 10, quota_bytes: 100},
          backup: {:error, :unreadable}
        })

      assert resumo == %{state: :attention, line: "Último backup falhou"}
    end
  end

  describe "disk_attention?/1" do
    test "verdadeiro no limite de 90% e acima, falso abaixo" do
      assert Saude.disk_attention?(%{used_bytes: 90, quota_bytes: 100})
      assert Saude.disk_attention?(%{used_bytes: 99, quota_bytes: 100})
      refute Saude.disk_attention?(%{used_bytes: 89, quota_bytes: 100})
    end

    test "falso para cota nil (disco inteiro) ou zerada" do
      refute Saude.disk_attention?(%{used_bytes: 900, quota_bytes: nil})
      refute Saude.disk_attention?(%{used_bytes: 900, quota_bytes: 0})
    end
  end

  describe "backup_attention?/1" do
    test "{:error, _} chama atencao; :none e {:ok, _} nao" do
      assert Saude.backup_attention?({:error, :no_dir})
      assert Saude.backup_attention?({:error, :unreadable})
      refute Saude.backup_attention?(:none)
      refute Saude.backup_attention?({:ok, %{at: DateTime.utc_now(), bytes: 1}})
    end
  end
end
