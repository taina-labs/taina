defmodule Ypy.Maraca.PersistenceTest do
  use Ypy.PersistenceCase, async: false

  import Ypy.Factories

  alias Ecto.Adapters.SQL.Sandbox
  alias Ypy.BrokenKeys
  alias Ypy.Maraca
  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Concessao
  alias Ypy.Maraca.Policy
  alias Ypy.Maraca.Store
  alias Ypy.RacyRepo
  alias Ypy.Scope
  alias Ypy.Ybira

  setup do
    {tekoa, keys} = nova_tekoa(TestRepo)
    {:ok, dono} = novo_ava(TestRepo, tekoa, username: "maria")
    {:ok, outro} = novo_ava(TestRepo, tekoa, username: "joao")
    {:ok, zelador} = novo_ava(TestRepo, tekoa, username: "zel", papel: :zelador)

    %{
      ## Concessao
      tekoa: tekoa,
      keys: keys,
      dono: dono,
      dono_scope: %Scope{ava: dono, tekoa: tekoa},
      outro: outro,
      outro_scope: %Scope{ava: outro, tekoa: tekoa},
      zelador: zelador,
      zelador_scope: %Scope{ava: zelador, tekoa: tekoa}
    }
  end

  test "conceder exige dono, mesma Tekoa e recurso ainda nao legivel", ctx do
    {:ok, file} = upload_na_casa(ctx, ctx.dono_scope)

    # So o dono concede.
    assert Maraca.conceder(
             TestRepo,
             ctx.keys,
             ctx.outro_scope,
             "ypy.file.v0",
             file.rkey,
             ctx.dono
           ) ==
             {:error, :not_owner}

    # O leitor tem de ser da mesma Tekoa.
    {outra_tekoa, _outras_keys} = nova_tekoa(TestRepo, name: "Outra", domain: "outra.test")
    {:ok, forasteiro} = novo_ava(TestRepo, outra_tekoa, username: "fora")

    assert Maraca.conceder(
             TestRepo,
             ctx.keys,
             ctx.dono_scope,
             "ypy.file.v0",
             file.rkey,
             forasteiro
           ) ==
             {:error, :cross_tekoa}

    # Conceder para si mesmo nao faz sentido: o dono ja le.
    assert Maraca.conceder(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", file.rkey, ctx.dono) ==
             {:error, :already_readable}

    {:ok, concessao} =
      Maraca.conceder(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", file.rkey, ctx.outro)

    assert concessao.leitor_id == ctx.outro.id
    assert concessao.dono_id == ctx.dono.id
    assert concessao.revogada_em == nil

    # Duas concessoes ativas do mesmo recurso para o mesmo leitor: uma so.
    assert Maraca.conceder(
             TestRepo,
             ctx.keys,
             ctx.dono_scope,
             "ypy.file.v0",
             file.rkey,
             ctx.outro
           ) ==
             {:error, :already_readable}

    tipos = Enum.map(Ypy.Mural.Store.cadeia(TestRepo, ctx.tekoa.id), & &1.tipo)
    assert tipos == ["put", "concessao"]
  end

  test "revogar e do dono e uma vez", ctx do
    {:ok, file} = upload_na_casa(ctx, ctx.dono_scope)

    {:ok, concessao} =
      Maraca.conceder(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", file.rkey, ctx.outro)

    assert Maraca.revogar(TestRepo, ctx.keys, ctx.outro_scope, concessao) ==
             {:error, :not_authorized}

    {:ok, revogada} = Maraca.revogar(TestRepo, ctx.keys, ctx.dono_scope, concessao)
    assert revogada.revogada_em

    assert Maraca.revogar(TestRepo, ctx.keys, ctx.dono_scope, revogada) ==
             {:error, :invalid_status}

    # Revogada, o leitor para de ler.
    assert Ybira.readable?(TestRepo, ctx.outro_scope, "ypy.file.v0", file.rkey) == false
  end

  test "pedir acesso: dono resolve do recurso e o que ja le nao pede", ctx do
    {:ok, file} = upload_na_casa(ctx, ctx.dono_scope)

    assert Maraca.pedir_acesso(TestRepo, ctx.dono_scope, "ypy.file.v0", file.rkey, "quero ver") ==
             {:error, :cannot_request_own}

    {:ok, pedido} =
      Maraca.pedir_acesso(TestRepo, ctx.outro_scope, "ypy.file.v0", file.rkey, "quero ver")

    assert pedido.status == :pendente
    assert pedido.dono_id == ctx.dono.id
    assert pedido.pedinte_id == ctx.outro.id

    # Pedido pendente duplicado: o indice unico nao deixa.
    assert {:error, %Ecto.Changeset{}} =
             Maraca.pedir_acesso(TestRepo, ctx.outro_scope, "ypy.file.v0", file.rkey, "de novo")
  end

  test "aprovar nasce a concessao e o pedido fecha; negar registra a decisao", ctx do
    {:ok, file} = upload_na_casa(ctx, ctx.dono_scope)

    {:ok, pedido} =
      Maraca.pedir_acesso(TestRepo, ctx.outro_scope, "ypy.file.v0", file.rkey, "quero ver")

    ## Pedido

    # A decisao e do dono, e so uma vez.
    assert Maraca.aprovar(TestRepo, ctx.keys, ctx.outro_scope, pedido) ==
             {:error, :not_authorized}

    {:ok, %{pedido: aprovado, concessao: concessao}} =
      Maraca.aprovar(TestRepo, ctx.keys, ctx.dono_scope, pedido)

    assert aprovado.status == :aprovado
    assert aprovado.decidido_em
    assert concessao.leitor_id == ctx.outro.id

    assert {:ok, _} = Ybira.get_file(TestRepo, ctx.outro_scope, file.rkey)

    assert Maraca.aprovar(TestRepo, ctx.keys, ctx.dono_scope, pedido) == {:error, :not_pending}

    # Aprovado duas vezes, uma concessao so nasceu.
    assert TestRepo.aggregate(Concessao, :count) == 1

    # Um pedido novo para o mesmo recurso agora esbarra no ja legivel.
    assert Maraca.pedir_acesso(TestRepo, ctx.outro_scope, "ypy.file.v0", file.rkey, "de novo") ==
             {:error, :already_has_access}

    # Negar: o dono decide, o pedido registra, nada muda de visibilidade.
    {:ok, pedido2} =
      Maraca.pedir_acesso(TestRepo, ctx.zelador_scope, "ypy.file.v0", file.rkey, "o zelador pede")

    {:ok, negado} = Maraca.negar(TestRepo, ctx.dono_scope, pedido2)
    assert negado.status == :negado

    assert Ybira.readable?(TestRepo, ctx.zelador_scope, "ypy.file.v0", file.rkey) == false
  end

  test "as listagens de pedido mostram recebidos e enviados", ctx do
    {:ok, file} = upload_na_casa(ctx, ctx.dono_scope)

    {:ok, _} =
      Maraca.pedir_acesso(TestRepo, ctx.outro_scope, "ypy.file.v0", file.rkey, "quero ver")

    assert length(Maraca.pedidos_recebidos(TestRepo, ctx.dono_scope)) == 1
    assert length(Maraca.pedidos_enviados(TestRepo, ctx.outro_scope)) == 1
    assert Maraca.pedidos_recebidos(TestRepo, ctx.outro_scope) == []
  end

  test "mudar papel e de zelador e protege a ultima zeladoria", ctx do
    # So zelador troca papel.
    assert Maraca.mudar_papel(TestRepo, ctx.keys, ctx.dono_scope, ctx.outro, :zelador) ==
             {:error, :not_authorized}

    {:ok, promovido} =
      Maraca.mudar_papel(TestRepo, ctx.keys, ctx.zelador_scope, ctx.outro, :zelador)

    assert promovido.papel == :zelador
    assert Store.count_zeladores(TestRepo, ctx.tekoa.id) == 2

    # Dois zeladores: pode destituir um, nao o outro.
    {:ok, _} = Maraca.mudar_papel(TestRepo, ctx.keys, ctx.zelador_scope, ctx.outro, :morador)

    assert Maraca.mudar_papel(TestRepo, ctx.keys, ctx.zelador_scope, ctx.zelador, :morador) ==
             {:error, :last_zelador}

    # Papel desconhecido nao passa no guard (o atomo nasce em runtime para o
    # type checker nao saber que e invalido).
    papel_invalido = String.to_atom("admin")

    assert_raise FunctionClauseError, fn ->
      Maraca.mudar_papel(TestRepo, ctx.keys, ctx.zelador_scope, ctx.outro, papel_invalido)
    end
  end

  test "commits concorrentes nao removem a ultima zeladoria", ctx do
    {:ok, segundo_zelador} =
      Maraca.mudar_papel(TestRepo, ctx.keys, ctx.zelador_scope, ctx.dono, :zelador)

    segundo_zelador_scope = %Scope{ava: segundo_zelador, tekoa: ctx.tekoa}
    RacyRepo.arm_concurrent_commit(self())

    tarefas =
      Enum.map(
        [
          {ctx.zelador_scope, segundo_zelador},
          {segundo_zelador_scope, ctx.zelador}
        ],
        fn {actor_scope, target} ->
          task =
            Task.async(fn ->
              receive do
                :start -> Maraca.mudar_papel(RacyRepo, ctx.keys, actor_scope, target, :morador)
              end
            end)

          :ok = Sandbox.allow(TestRepo, self(), task.pid)
          send(task.pid, :start)
          task
        end
      )

    try do
      synchronize_racy_repo()
      resultados = Enum.map(tarefas, &Task.await(&1, :infinity))

      assert Enum.count(resultados, &match?({:ok, %Ava{}}, &1)) == 1
      assert Enum.count(resultados, &(&1 == {:error, :last_zelador})) == 1
      assert Store.count_zeladores(TestRepo, ctx.tekoa.id) == 1

      assert length(Ypy.Mural.Store.entradas(TestRepo, ctx.tekoa.id, tipo: "mudar_papel")) == 2
    after
      RacyRepo.disarm()
    end
  end

  test "mudar papel e um ato na cadeia, do mesmo commit da mudanca", ctx do
    {:ok, promovido} =
      Maraca.mudar_papel(TestRepo, ctx.keys, ctx.zelador_scope, ctx.outro, :zelador)

    assert promovido.papel == :zelador

    entrada = Ypy.Mural.Store.entrada(TestRepo, ctx.tekoa.id, 1)

    assert entrada.tipo == "mudar_papel"

    assert entrada.payload == %{
             "tipo" => "mudar_papel",
             "actor" => ctx.zelador.public_id,
             "ava" => ctx.outro.public_id,
             "papel" => "zelador"
           }

    ## Papel
    assert Ypy.Mural.Store.verificar_cadeia(TestRepo, ctx.tekoa.id) == :ok

    # A cadeia falhou, o papel nao mudou: o ato e um so fato.
    quebradas = BrokenKeys.new(dir_temporario("keys-quebradas-papel"))

    assert Maraca.mudar_papel(TestRepo, quebradas, ctx.zelador_scope, ctx.outro, :morador) ==
             {:error, :not_found}

    assert TestRepo.reload!(ctx.outro).papel == :zelador
  end

  test "ava pendente e aceite de convite, invariantes do kernel", ctx do
    token_hash = :sha256 |> :crypto.hash("token-cru") |> Base.encode64(padding: false)
    agora = DateTime.truncate(DateTime.utc_now(), :second)

    {:ok, pendente} =
      TestRepo.insert(
        Ava.invitation_changeset(%Ava{}, %{
          tekoa_id: ctx.tekoa.id,
          invited_by_id: ctx.dono.id,
          papel: :morador,
          invite_token_hash: token_hash,
          invite_sent_at: agora,
          invited_at: agora
        })
      )

    assert Ava.active?(pendente) == false

    {:ok, ativo} =
      TestRepo.update(
        Ava.accept_changeset(pendente, %{
          username: "nova_pessoa",
          password: "senhaforte123"
        })
      )

    assert Ava.active?(ativo) == true
    assert ativo.password_hash
    assert Bcrypt.verify_pass("senhaforte123", ativo.password_hash)

    # Expiracao do convite (politica pura sobre a coluna).
    assert Policy.invite_expired?(agora, DateTime.shift(agora, day: 8)) == true
    assert Policy.invite_expired?(agora, agora) == false
  end

  defp upload_na_casa(ctx, scope) do
    path = Path.join(dir_temporario("upload"), "foto")

    File.write!(path, "conteudo da foto")

    {:ok, file} =
      Ybira.upload(TestRepo, ctx.keys, blobs(), scope, path, mime: "image/jpeg")

    {:ok, file}
  end

  defp synchronize_racy_repo do
    {phase, first_pid} =
      receive do
        {:racy_repo_waiting, phase, pid} -> {phase, pid}
      after
        5_000 -> flunk("no concurrent repo operation reached the barrier")
      end

    phase_pids = [first_pid | waiting_racy_repo(phase, 1)]
    Enum.each(phase_pids, &send(&1, {:racy_repo_continue, phase}))

    if phase == :count do
      transaction_pids = waiting_racy_repo(:transaction, 2)
      Enum.each(transaction_pids, &send(&1, {:racy_repo_continue, :transaction}))
    end
  end

  defp waiting_racy_repo(phase, count) do
    Enum.map(1..count, fn _ ->
      receive do
        {:racy_repo_waiting, ^phase, pid} -> pid
      after
        5_000 -> flunk("concurrent repo operation did not reach #{phase} barrier")
      end
    end)
  end
end
