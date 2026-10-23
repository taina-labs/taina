defmodule Ypy.Assembleia.PersistenceTest do
  use Ypy.PersistenceCase, async: false

  import Ypy.Factories

  alias Ypy.Assembleia
  alias Ypy.Scope

  setup do
    {tekoa, _keys} = nova_tekoa(TestRepo)
    {:ok, zelador} = novo_ava(TestRepo, tekoa, username: "zel", papel: :zelador)
    {:ok, a} = novo_ava(TestRepo, tekoa, username: "maria")
    {:ok, b} = novo_ava(TestRepo, tekoa, username: "joao")

    %{
      tekoa: tekoa,
      zelador: zelador,
      zelador_scope: %Scope{ava: zelador, tekoa: tekoa},
      a: a,
      a_scope: %Scope{ava: a, tekoa: tekoa},
      b: b,
      b_scope: %Scope{ava: b, tekoa: tekoa}
    }
  end

  defp abrir(_ctx, scope, tipo \\ :remover_morador, payload \\ %{"morador" => "public123"}, prazos \\ []) do
    fecha_em =
      DateTime.utc_now()
      |> DateTime.shift(day: Keyword.get(prazos, :dias, 7))
      |> DateTime.truncate(:second)

    Assembleia.abrir(TestRepo, scope, tipo, payload, fecha_em: fecha_em)
  end

  test "o ciclo completo: abre, vota, apura aprovada e executa uma vez", ctx do
    {:ok, proposta} = abrir(ctx, ctx.a_scope)

    assert proposta.status == :aberta
    assert proposta.tipo == :remover_morador
    assert proposta.payload == %{"morador" => "public123"}

    # Um voto por pessoa.
    {:ok, _} = Assembleia.votar(TestRepo, ctx.a_scope, proposta, :sim)
    {:ok, _} = Assembleia.votar(TestRepo, ctx.zelador_scope, proposta, :nao)

    assert {:error, %Ecto.Changeset{}} =
             Assembleia.votar(TestRepo, ctx.a_scope, proposta, :sim)

    # 3 moradores, quorum ceil(3/2) = 2; terceiro voto diz sim.
    {:ok, _} = Assembleia.votar(TestRepo, ctx.b_scope, proposta, :sim)

    {:ok, fechada} = Assembleia.fechar(TestRepo, ctx.tekoa.id, proposta)
    assert fechada.status == :aprovada

    # Fechar de novo nao re-apura.
    assert Assembleia.fechar(TestRepo, ctx.tekoa.id, proposta) == {:error, :invalid_status}

    {:ok, executada} = Assembleia.executar(TestRepo, ctx.tekoa.id, fechada)
    assert executada.executado_em

    # A reclamacao unica: o ato aprovado so roda uma vez.
    assert Assembleia.executar(TestRepo, ctx.tekoa.id, fechada) == {:error, :already_executed}
  end

  test "quorum faltando expira, mesmo com todos os poucos dizendo sim", ctx do
    # 4 moradores, quorum ceil(4/2) = 2; so 1 vota.
    {:ok, _c} = novo_ava(TestRepo, ctx.tekoa, username: "cris")

    {:ok, proposta} = abrir(ctx, ctx.a_scope)
    {:ok, _} = Assembleia.votar(TestRepo, ctx.a_scope, proposta, :sim)

    assert TestRepo |> Assembleia.Store.escolhas(ctx.tekoa.id, proposta.id) |> length() == 1
    assert Ypy.Maraca.Store.count_moradores(TestRepo, ctx.tekoa.id) == 4

    {:ok, fechada} = Assembleia.fechar(TestRepo, ctx.tekoa.id, proposta)
    assert fechada.status == :expirada

    # Expirada nao executa ato nenhum.
    assert Assembleia.executar(TestRepo, ctx.tekoa.id, fechada) == {:error, :invalid_status}
  end

  test "quorum com maioria nao aprova", ctx do
    {:ok, proposta} = abrir(ctx, ctx.a_scope)

    {:ok, _} = Assembleia.votar(TestRepo, ctx.a_scope, proposta, :sim)
    {:ok, _} = Assembleia.votar(TestRepo, ctx.zelador_scope, proposta, :nao)
    {:ok, _} = Assembleia.votar(TestRepo, ctx.b_scope, proposta, :nao)

    {:ok, fechada} = Assembleia.fechar(TestRepo, ctx.tekoa.id, proposta)
    assert fechada.status == :rejeitada
  end

  test "voto fora do prazo e recusado e a proposta fecha expirada depois", ctx do
    {:ok, proposta} = abrir(ctx, ctx.a_scope, :mudar_cota, %{"cota" => 1_000_000}, dias: -1)

    assert Assembleia.votar(TestRepo, ctx.a_scope, proposta, :sim) == {:error, :expirada}

    {:ok, fechada} = Assembleia.fechar(TestRepo, ctx.tekoa.id, proposta)
    assert fechada.status == :expirada
  end

  test "proposta e escopada pela Tekoa em toda a leitura", ctx do
    {outra, _keys} = nova_tekoa(TestRepo, name: "Outra", domain: "outra.test")
    {:ok, forasteiro} = novo_ava(TestRepo, outra, username: "fora")

    {:ok, proposta} = abrir(ctx, ctx.a_scope)

    assert Assembleia.votar(TestRepo, %Scope{ava: forasteiro, tekoa: outra}, proposta, :sim) ==
             {:error, :cross_tekoa}

    # Ler por outra Tekoa e nao achar (a proposta de la nao existe para la).
    assert Assembleia.fechar(TestRepo, outra.id, proposta) == {:error, :not_found}
    assert Assembleia.executar(TestRepo, outra.id, proposta) == {:error, :not_found}

    assert Assembleia.Store.get_proposta(TestRepo, outra.id, proposta.public_id) == nil
  end

  test "tipo fora do vocabulario nao abre proposta", ctx do
    # O atomo nasce em runtime para o type checker nao saber que e invalido
    # (e o teste afirmar o raise do guard).
    tipo_invalido = String.to_atom("dar_poder_ao_zelador")

    assert_raise FunctionClauseError, fn ->
      abrir(ctx, ctx.a_scope, tipo_invalido)
    end
  end

  test "executar proposta nao aprovada nao roda", ctx do
    {:ok, proposta} = abrir(ctx, ctx.a_scope)
    assert Assembleia.executar(TestRepo, ctx.tekoa.id, proposta) == {:error, :invalid_status}
  end

  test "as listagens filtram por status e trazem os votos", ctx do
    {:ok, proposta} = abrir(ctx, ctx.a_scope)
    {:ok, _} = Assembleia.votar(TestRepo, ctx.a_scope, proposta, :sim)

    abertas = Assembleia.propostas(TestRepo, ctx.tekoa.id, status: :aberta)
    assert Enum.map(abertas, & &1.id) == [proposta.id]

    votos = Assembleia.votos(TestRepo, ctx.tekoa.id, proposta)
    assert Enum.map(votos, & &1.escolha) == [:sim]
    assert Enum.map(votos, & &1.ava_id) == [ctx.a.id]
  end
end
