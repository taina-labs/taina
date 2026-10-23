defmodule Ypy.Maraca.PersistenceTest do
  use Ypy.PersistenceCase, async: false

  import Ypy.Factories

  alias Ypy.BrokenKeys
  alias Ypy.Maraca
  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Credentials
  alias Ypy.Maraca.Policy
  alias Ypy.Maraca.Store
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

    tipos = Enum.map(Ypy.Mural.entradas(TestRepo, ctx.tekoa.id), & &1.tipo)
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

  test "mudar papel e um ato na cadeia, do mesmo commit da mudanca", ctx do
    {:ok, promovido} =
      Maraca.mudar_papel(TestRepo, ctx.keys, ctx.zelador_scope, ctx.outro, :zelador)

    assert promovido.papel == :zelador

    entrada = Ypy.Mural.entrada(TestRepo, ctx.tekoa.id, 1)

    assert entrada.tipo == "mudar_papel"

    assert entrada.payload == %{
             "tipo" => "mudar_papel",
             "actor" => ctx.zelador.public_id,
             "ava" => ctx.outro.public_id,
             "papel" => "zelador"
           }

    ## Papel
    assert Ypy.Mural.verificar_cadeia(TestRepo, ctx.tekoa.id) == :ok

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
    assert Credentials.valid_password?("senhaforte123", ativo.password_hash)

    # Expiracao do convite (politica pura sobre a coluna).
    assert Policy.invite_expired?(agora, DateTime.shift(agora, day: 3)) == true
    assert Policy.invite_expired?(agora, agora) == false
  end

  defp upload_na_casa(ctx, scope) do
    path = Path.join(dir_temporario("upload"), "foto")

    File.write!(path, "conteudo da foto")

    {:ok, file} =
      Ybira.upload(TestRepo, ctx.keys, blobs(), scope, path, mime: "image/jpeg")

    {:ok, file}
  end
end
