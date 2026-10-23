defmodule Ypy.Maraca do
  @moduledoc """
  Os verbos sociais do Maraca: concessao, pedido, decisao do dono e troca de
  papel.

  Os fluxos de autenticacao (convite, login, reset) ficam no produto (RFC_006
  D10); daqui sai so o que muda fato social. Concessao, revogacao e troca de
  papel anexam entrada na cadeia (RFC_006 secao 8) no mesmo commit do dado:
  ou o fato social fica com a sua entrada, ou nada fica.
  """

  alias Ypy.KeyStore
  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Concessao

  ## Concessao

  alias Ypy.Maraca.Pedido
  alias Ypy.Maraca.Store
  alias Ypy.Mural.Store, as: MuralStore
  alias Ypy.Scope
  alias Ypy.Ybira

  @tipos ["ypy.file.v0", "ypy.folder.v0"]

  @doc """
  Abre a propria casa para um leitor (RFC_003 D2). O recurso tem de ser do
  quem concede, o leitor tem de ser da mesma Tekoa e nao pode ja ler o
  recurso (praca, dono ou concessao ativa valem).
  """
  @spec conceder(Ecto.Repo.t(), KeyStore.t(), Scope.t(), String.t(), String.t(), Ava.t()) ::
          {:ok, Concessao.t()} | {:error, term()}
  def conceder(repo, keys, %Scope{} = scope, tipo, rkey, %Ava{} = leitor) when tipo in @tipos do
    with :ok <- mesma_tekoa(scope, leitor),
         :ok <- nao_e_leitor_proprio(scope, leitor),
         {:ok, row} <- Ybira.recurso(repo, scope.tekoa.id, tipo, rkey),
         :ok <- dono_guard(row, scope),
         :ok <- nao_legivel(repo, scope, leitor, tipo, rkey) do
      MuralStore.commit(
        repo,
        keys,
        scope.tekoa.id,
        "concessao",
        %{
          "actor" => scope.ava.public_id,
          "leitor" => leitor.public_id,
          "collection" => tipo,
          "recurso" => rkey
        },
        fn ->
          Store.insert(
            repo,
            Concessao.changeset(%Concessao{}, %{
              tekoa_id: scope.tekoa.id,
              leitor_id: leitor.id,
              dono_id: scope.ava.id,
              tipo: tipo,
              recurso: rkey,
              concedida_em: agora()
            })
          )
        end
      )
    end
  end

  @doc "Revoga a concessao ativa. So quem concedeu; revogar de novo e erro."
  @spec revogar(Ecto.Repo.t(), KeyStore.t(), Scope.t(), Concessao.t()) ::
          {:ok, Concessao.t()} | {:error, term()}
  def revogar(repo, keys, %Scope{} = scope, %Concessao{} = concessao) do
    with :ok <- mesma_tekoa_row(scope, concessao.tekoa_id),
         :ok <- if(concessao.dono_id == scope.ava.id, do: :ok, else: {:error, :not_authorized}),
         :ok <- if(concessao.revogada_em, do: {:error, :invalid_status}, else: :ok) do
      ## Pedido
      MuralStore.commit(
        repo,
        keys,
        scope.tekoa.id,
        "revogar",
        %{
          "actor" => scope.ava.public_id,
          "collection" => concessao.tipo,
          "recurso" => concessao.recurso,
          "leitor" => leitor_public_id(repo, scope.tekoa.id, concessao.leitor_id)
        },
        fn ->
          Store.update(repo, Concessao.revoke_changeset(concessao, agora()))
        end
      )
    end
  end

  @doc """
  Pede ao dono a leitura de um recurso da casa dele. O dono e resolvido do
  proprio recurso; pedir o proprio recurso e pedir o que ja se le valem
  erro, e o pedido nasce :pendente.
  """
  @spec pedir_acesso(Ecto.Repo.t(), Scope.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, Pedido.t()} | {:error, term()}
  def pedir_acesso(repo, %Scope{} = scope, tipo, rkey, motivo) when tipo in @tipos do
    with {:ok, row} <- Ybira.recurso(repo, scope.tekoa.id, tipo, rkey),
         :ok <- if(row.dono_id == scope.ava.id, do: {:error, :cannot_request_own}, else: :ok),
         :ok <-
           if(Ybira.readable?(repo, scope, tipo, rkey),
             do: {:error, :already_has_access},
             else: :ok
           ) do
      Store.insert(
        repo,
        Pedido.changeset(%Pedido{}, %{
          tekoa_id: scope.tekoa.id,
          pedinte_id: scope.ava.id,
          dono_id: row.dono_id,
          tipo: tipo,
          recurso: rkey,
          motivo: motivo
        })
      )
    end
  end

  @doc "Aprova o pedido pendente: nasce a concessao (entrada na cadeia)."
  @spec aprovar(Ecto.Repo.t(), KeyStore.t(), Scope.t(), Pedido.t()) ::
          {:ok, %{pedido: Pedido.t(), concessao: Concessao.t()}} | {:error, term()}
  ## Papel
  def aprovar(repo, keys, %Scope{} = scope, %Pedido{} = pedido) do
    with {:ok, pedido} <- pedido_atual(repo, scope.tekoa.id, pedido),
         :ok <- if(pedido.dono_id == scope.ava.id, do: :ok, else: {:error, :not_authorized}),
         :ok <- pendente_guard(pedido),
         {:ok, concessao} <- conceder_por_pedido(repo, keys, scope, pedido) do
      {:ok, pedido} = Store.update(repo, Pedido.decide_changeset(pedido, :aprovado, agora()))
      {:ok, %{pedido: pedido, concessao: concessao}}
    end
  end

  @doc "Nega o pedido pendente. Nada muda de visibilidade, o pedido registra."
  @spec negar(Ecto.Repo.t(), Scope.t(), Pedido.t()) ::
          {:ok, Pedido.t()} | {:error, term()}
  def negar(repo, %Scope{} = scope, %Pedido{} = pedido) do
    with {:ok, pedido} <- pedido_atual(repo, scope.tekoa.id, pedido),
         :ok <- if(pedido.dono_id == scope.ava.id, do: :ok, else: {:error, :not_authorized}),
         :ok <- pendente_guard(pedido) do
      Store.update(repo, Pedido.decide_changeset(pedido, :negado, agora()))
    end
  end

  @doc """
  Troca o papel de um morador e anexa o ato na cadeia (RFC_006 secao 8): a
  entrada e um fato assinado do mesmo commit que a mudanca. Quem troca e
  zelador, e a ultima zeladoria fica: destituir quem a segura sozinho
  responde {:error, :last_zelador} (RFC_003: o cuidado da maquina se
  distribui, nao se esvazia).
  """

  ## Listagens

  @spec mudar_papel(Ecto.Repo.t(), KeyStore.t(), Scope.t(), Ava.t(), :zelador | :morador) ::
          {:ok, Ava.t()} | {:error, term()}
  def mudar_papel(repo, keys, %Scope{} = scope, %Ava{id: ava_id}, papel) when papel in [:zelador, :morador] do
    with :ok <- zelador_guard(scope),
         {:ok, ava} <- ava_atual(repo, scope.tekoa.id, ava_id),
         :ok <- ultimo_zelador_guard(repo, scope, ava, papel) do
      MuralStore.commit(
        repo,
        keys,
        scope.tekoa.id,
        "mudar_papel",
        ## Internos
        %{
          "actor" => scope.ava.public_id,
          "ava" => ava.public_id,
          "papel" => Atom.to_string(papel)
        },
        fn ->
          Store.update(repo, Ava.papel_changeset(ava, papel))
        end
      )
    end
  end

  @doc "Os pedidos pendentes que o morador recebeu como dono."
  def pedidos_recebidos(repo, %Scope{} = scope), do: Store.pedidos_recebidos(repo, scope.tekoa.id, scope.ava.id)

  @doc "Os pedidos que o morador fez."
  def pedidos_enviados(repo, %Scope{} = scope), do: Store.pedidos_enviados(repo, scope.tekoa.id, scope.ava.id)

  @doc "As concessoes que o morador concedeu, ativas e aposentadas."
  def concessoes_concedidas(repo, %Scope{} = scope), do: Store.concessoes_concedidas(repo, scope.tekoa.id, scope.ava.id)

  defp mesma_tekoa(%Scope{tekoa: %{id: tekoa_id}}, %Ava{tekoa_id: ava_tekoa_id}) when tekoa_id == ava_tekoa_id, do: :ok

  defp mesma_tekoa(_scope, _ava), do: {:error, :cross_tekoa}

  defp mesma_tekoa_row(%Scope{tekoa: %{id: tekoa_id}}, tekoa_id2) when tekoa_id == tekoa_id2, do: :ok

  defp mesma_tekoa_row(_scope, _tekoa_id), do: {:error, :cross_tekoa}

  defp nao_e_leitor_proprio(%Scope{ava: %{id: ava_id}}, %Ava{id: leitor_id}) when ava_id == leitor_id,
    do: {:error, :already_readable}

  defp nao_e_leitor_proprio(_scope, _leitor), do: :ok

  defp dono_guard(row, scope) do
    if row.dono_id == scope.ava.id, do: :ok, else: {:error, :not_owner}
  end

  defp nao_legivel(repo, scope, leitor, tipo, rkey) do
    leitor_scope = %Scope{ava: leitor, tekoa: scope.tekoa}

    if Ybira.readable?(repo, leitor_scope, tipo, rkey),
      do: {:error, :already_readable},
      else: :ok
  end

  # O estado do pedido pode ter mudado desde o struct em maos (o dono decidiu
  # por outra janela): reler antes de guardar, dentro da Tekoa.
  defp pedido_atual(repo, tekoa_id, %Pedido{id: id}) do
    case Store.get_pedido(repo, tekoa_id, id) do
      %Pedido{} = pedido -> {:ok, pedido}
      nil -> {:error, :not_found}
    end
  end

  # O papel pode ter mudado desde o struct em maos (outro zelador decidiu por
  # outra janela): reler antes de julgar a ultima zeladoria.
  defp ava_atual(repo, tekoa_id, ava_id) do
    case Store.get_ava(repo, tekoa_id, ava_id) do
      %Ava{} = ava -> {:ok, ava}
      nil -> {:error, :not_found}
    end
  end

  defp pendente_guard(%Pedido{status: :pendente}), do: :ok
  defp pendente_guard(_pedido), do: {:error, :not_pending}

  defp zelador_guard(%Scope{ava: %Ava{papel: :zelador}}), do: :ok
  defp zelador_guard(_scope), do: {:error, :not_authorized}

  defp ultimo_zelador_guard(repo, scope, ava, :morador) do
    if ava.papel == :zelador and Store.count_zeladores(repo, scope.tekoa.id) == 1,
      do: {:error, :last_zelador},
      else: :ok
  end

  defp ultimo_zelador_guard(_repo, _scope, _ava, :zelador), do: :ok

  defp conceder_por_pedido(repo, keys, scope, pedido) do
    leitor = Store.get_ava(repo, scope.tekoa.id, pedido.pedinte_id)

    with {:ok, leitor} <- if(leitor, do: {:ok, leitor}, else: {:error, :not_found}) do
      MuralStore.commit(
        repo,
        keys,
        scope.tekoa.id,
        "concessao",
        %{
          "actor" => scope.ava.public_id,
          "leitor" => leitor.public_id,
          "collection" => pedido.tipo,
          "recurso" => pedido.recurso,
          "via" => "pedido",
          "pedido" => pedido.public_id
        },
        fn ->
          Store.insert(
            repo,
            Concessao.changeset(%Concessao{}, %{
              tekoa_id: scope.tekoa.id,
              leitor_id: leitor.id,
              dono_id: scope.ava.id,
              tipo: pedido.tipo,
              recurso: pedido.recurso,
              concedida_em: agora()
            })
          )
        end
      )
    end
  end

  defp leitor_public_id(repo, tekoa_id, leitor_id) do
    case Store.get_ava(repo, tekoa_id, leitor_id) do
      %Ava{public_id: public_id} -> public_id
      nil -> nil
    end
  end

  defp agora, do: DateTime.truncate(DateTime.utc_now(), :second)
end
