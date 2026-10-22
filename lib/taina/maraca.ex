defmodule Taina.Maraca do
  @moduledoc """
  O Maraca do produto, sobre o kernel Ypy.

  Os verbos sociais (concessao, pedido, decisao do dono, troca de papel) sao
  do kernel (`Ypy.Maraca`), que anexa cada ato a cadeia unica; aqui ficam os
  fluxos de autenticacao e UX do box (RFC_006 D10): convite, aceite, login
  com rate limit, sessao, reset mediado pelo zelador, ciclo de vida da conta
  e a trava de uma-Tekoa-por-box. O mural e a projecao da cadeia
  (`maraca_mural`), nao uma tabela propria.

  ## Filosofia

  - **Moradores sao donos dos seus dados** - propriedade explicita
  - **Zeladores cuidam da maquina, nao sao deuses** - pedem acesso como
    qualquer morador (o kernel nao da atalho)
  - **Concessoes explicitas** - nunca implicitas, cada uma uma entrada
    assinada na cadeia
  """

  import Ecto.Query

  alias Taina.Keys
  alias Taina.Maraca.DeviceToken
  alias Taina.RateLimit
  alias Taina.Repo
  alias Taina.Scope
  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Concessao
  alias Ypy.Maraca.Pedido
  alias Ypy.Maraca.Policy
  alias Ypy.Maraca.Store, as: KernelStore
  alias Ypy.Maraca.Tekoa
  alias Ypy.Mural.Store, as: MuralStore
  alias Ypy.PublicId

  require Logger

  @invitation_max_age_seconds 7 * 24 * 60 * 60
  @reset_max_age_seconds 60 * 60

  # Janela de força bruta de login, por (tekoa, username): no máximo
  # @login_rate_limit tentativas a cada @login_rate_scale_ms. Folgado o
  # suficiente para erros de digitação, apertado contra enumeração de senha.
  @login_rate_scale_ms 60_000
  @login_rate_limit 5

  @event_page_limit 50

  @kernel_tipos ["ypy.file.v0", "ypy.folder.v0"]

  @doc """
  Cria a Tekoa e o zelador dela, com a chave que assina a cadeia. A trava de
  uma-Tekoa-por-box e do banco (indice unico `single_tekoa_enforcement`,
  RFC_006 D11); a checagem adiantada evita o erro feio, e fica na mesma
  transacao para duas inicializacoes concorrentes nao passarem ambas.

  O `domain` (a identidade `did:web` da Tekoa) vem nos attrs quando quem
  instala declara o endereco da caixa; sem ele, o default do spike vale
  (`tekoa.local`) ate o wizard de setup coletar o endereco.
  """
  def bootstrap(tekoa_attrs, zelador_attrs) do
    tekoa_attrs = Map.put_new(tekoa_attrs, :domain, "tekoa.local")

    Repo.with_system(fn ->
      if Repo.exists?(Tekoa, skip_tekoa_id: true) do
        {:error, :already_bootstrapped}
      else
        create_tekoa_with_zelador(tekoa_attrs, zelador_attrs)
      end
    end)
  end

  defp create_tekoa_with_zelador(tekoa_attrs, zelador_attrs) do
    with {:ok, tekoa} <- Repo.insert(Tekoa.changeset(%Tekoa{}, tekoa_attrs)),
         :ok <- Keys.mint(Repo, tekoa.id),
         {:ok, ava} <- insert_bootstrap_zelador(tekoa, zelador_attrs) do
      {:ok, %{tekoa: tekoa, ava: ava}}
    end
  end

  # O zelador de bootstrap nasce no papel: o kernel aceita so
  # username/display_name/password no accept_changeset, o papel e daqui.
  defp insert_bootstrap_zelador(%Tekoa{} = tekoa, attrs) do
    ## Membros
    %Ava{tekoa_id: tekoa.id}
    |> Ava.accept_changeset(Map.take(attrs, [:username, :display_name, :password]))
    |> Ecto.Changeset.change(papel: :zelador)
    |> Repo.insert()
  end

  @doc "A caixa ja tem Tekoa? Consulta de sistema: roda antes de haver contexto."
  def bootstrapped? do
    {:ok, exists?} =
      Repo.with_system(fn -> {:ok, Repo.exists?(Tekoa, skip_tekoa_id: true)} end)

    exists?
  end

  @doc "A Tekoa da caixa (una por construcao, RFC_006 D11)."
  def get_tekoa do
    ## Convite e aceite
    Repo.with_system(fn ->
      case Repo.one(Tekoa, skip_tekoa_id: true) do
        %Tekoa{} = tekoa -> {:ok, tekoa}
        nil -> {:error, :not_bootstrapped}
      end
    end)
  end

  def list_members(%Ypy.Scope{} = scope) do
    within_tekoa(scope, fn ->
      members =
        from(a in Ava,
          where: a.tekoa_id == ^scope.tekoa.id,
          order_by: [asc: fragment("CASE WHEN ? = 'zelador' THEN 0 ELSE 1 END", a.papel), asc: a.inserted_at]
        )

      {:ok, Repo.all(members)}
    end)
  end

  def count_members(%Ypy.Scope{} = scope) do
    within_tekoa(scope, fn ->
      {:ok, Repo.aggregate(from(a in Ava, where: a.tekoa_id == ^scope.tekoa.id), :count)}
    end)
  end

  @doc """
  O convite (fluxo do produto): um Ava pendente com token hasheado; o token
  cru volta pro chamador montar o link/QR. O registro do mural vai para a
  cadeia depois do commit: a escrita do ledger e consequencia, e nao pode
  derrubar o convite.
  """
  def invite_user(%Ava{} = zelador, %Tekoa{} = tekoa, opts \\ []) do
    if zelador?(zelador) and zelador.tekoa_id == tekoa.id do
      raw_token = generate_token()

      attrs = %{
        tekoa_id: tekoa.id,
        invited_by_id: zelador.id,
        papel: Keyword.get(opts, :role, :morador),
        invite_token_hash: hash_token(raw_token),
        invite_sent_at: agora(),
        invited_at: agora()
      }

      result =
        Repo.with_tekoa(tekoa.public_id, fn ->
          Repo.insert(Ava.invitation_changeset(%Ava{}, attrs))
        end)

      with {:ok, ava} <- result do
        record_event(Scope.new(zelador, tekoa), :invite_created, %{
          "role" => Atom.to_string(attrs.papel)
        })

        {:ok, %{ava: ava, token: raw_token}}
      end
    else
      {:error, :not_zelador}
    end
  end

  @doc """
  O aceite do convite: username, display_name e senha; a conta ativa. Token
  expirado, conta desativada ou confirmacao de senha errada recusam. O papel
  vai no registro do mural para o aceite de zelador ser legivel na cadeia.
  """
  def accept_invite(token, attrs) do
    with %Ava{} = ava <- find_by_token(:invite_token_hash, token),
         false <- token_expired?(ava.invite_sent_at, @invitation_max_age_seconds),
         ## Autenticação e sessão
         nil <- ava.deactivated_at,
         :ok <- confirmation_ok?(attrs) do
      result =
        Repo.with_tekoa(tekoa_public_id(ava), fn -> aceitar_convite(ava, attrs) end)

      with {:ok, %{ava: accepted, tekoa: tekoa}} <- result do
        record_event(Scope.new(accepted, tekoa), :invite_accepted, %{
          "role" => Atom.to_string(accepted.papel)
        })

        {:ok, accepted}
      end
    else
      _ -> {:error, :invalid_token}
    end
  end

  # O attrs cru entra no changeset do kernel: o cast (nome, display e
  # senha) e a whitelist, e aceita chaves de string ou atomo.
  defp aceitar_convite(ava, attrs) do
    with {:ok, accepted} <- Repo.update(Ava.accept_changeset(ava, attrs)) do
      {:ok, %{ava: accepted, tekoa: Repo.get!(Tekoa, accepted.tekoa_id)}}
    end
  end

  # A confirmacao de senha e fluxo do produto (o kernel cobra so a senha).
  defp confirmation_ok?(attrs) do
    password = fetch_attr(attrs, :password)
    confirmation = fetch_attr(attrs, :password_confirmation)

    if confirmation in [nil, password], do: :ok, else: {:error, :password_mismatch}
  end

  @doc "Um convite pendente cujo token ja passou da validade."
  def invite_expired?(%Ava{} = ava) do
    token_expired?(ava.invite_sent_at, @invitation_max_age_seconds)
  end

  @doc """
  Status de um convite pelo token cru, sem consumir nada: `:ok` quando o link
  ainda vale (conta pendente, não expirada, não desativada); `:invalid` caso
  contrário. Espelha as condições de `accept_invite/2` para a tela de aceite
  mostrar o beco sem saída antes de a pessoa preencher o formulário inteiro.
  """
  def invite_status(token) do
    case find_by_token(:invite_token_hash, token) do
      %Ava{deactivated_at: nil} = ava ->
        if token_expired?(ava.invite_sent_at, @invitation_max_age_seconds), do: :invalid, else: :ok

      _ ->
        :invalid
    end
  end

  @doc "Login por username e senha, com rate limit de força bruta (fluxo do produto)."
  def authenticate(username, password, %Tekoa{} = tekoa) do
    username = Ypy.Handle.normalize(to_string(username))
    key = login_rate_key(tekoa, username)

    if login_rate_exceeded?(key) do
      {:error, :rate_limited}
    else
      case do_authenticate(username, password, tekoa) do
        {:ok, ava} -> {:ok, ava}
        {:error, _reason} = error -> record_login_failure(key, error)
      end
    end
  end

  defp do_authenticate(username, password, %Tekoa{} = tekoa) do
    {:ok, result} =
      Repo.with_tekoa(tekoa.public_id, fn ->
        {:ok, KernelStore.get_ava_por_username(Repo, tekoa.id, username)}
      end)

    verify_credentials(result, password)
  end

  defp login_rate_key(%Tekoa{} = tekoa, username), do: "login:#{tekoa.public_id}:#{username}"

  # Só as falhas contam para a janela: lemos a contagem sem incrementar, então
  # uma senha correta nunca a queima (login/logout/login não tranca ninguém).
  # Acima do limite recusamos antes do bcrypt, blindando a CPU contra força
  ## Gestão da Tekoa

  # bruta. Conta inexistente compartilha a janela do username (não vaza existência).
  defp login_rate_exceeded?(key) do
    RateLimit.get(key, @login_rate_scale_ms) >= @login_rate_limit
  end

  defp record_login_failure(key, error) do
    _ = RateLimit.hit(key, @login_rate_scale_ms, @login_rate_limit)
    error
  end

  defp verify_credentials(nil, _password) do
    Bcrypt.no_user_verify()
    {:error, :invalid_credentials}
  end

  # Conta desativada pelo zelador: bloqueia login mesmo com senha correta.
  defp verify_credentials(%Ava{deactivated_at: deactivated_at}, _password) when not is_nil(deactivated_at) do
    Bcrypt.no_user_verify()
    {:error, :account_deactivated}
  end

  # Convite ainda não aceito: sem senha definida, não há o que verificar.
  defp verify_credentials(%Ava{password_hash: nil}, _password) do
    Bcrypt.no_user_verify()
    {:error, :invalid_credentials}
  end

  # Falha de credencial e um erro so: quem troca a propria senha nao distingue
  # "senha errada" de conta desativada (conta desativada nem chega logada).
  # Valor que nao e texto (JSON sem tipo) nao chega ao bcrypt, que levantaria:
  # o contrato e o de senha errada, com o no-op do bcrypt pelo meio.
  defp verify_credentials(%Ava{}, password) when not is_binary(password) do
    Bcrypt.no_user_verify()
    {:error, :invalid_credentials}
  end

  defp verify_credentials(%Ava{} = ava, password) do
    if Bcrypt.verify_pass(password, ava.password_hash) do
      {:ok, ava}
    else
      {:error, :invalid_credentials}
    end
  end

  def create_session(%Ava{} = ava) do
    %{ava_id: ava.public_id, tekoa_id: tekoa_public_id(ava), papel: ava.papel}
  end

  def destroy_session(%Plug.Conn{} = conn) do
    conn
    |> Plug.Conn.clear_session()
    |> Plug.Conn.configure_session(drop: true)
  end

  def get_session_user(%Plug.Conn{} = conn) do
    conn |> Plug.Conn.get_session(:ava_id) |> resolve_session_ava()
  end

  # LiveView `on_mount` recebe o mapa de sessão (chaves string), não a conn.
  def get_session_user(%{"ava_id" => ava_id}), do: resolve_session_ava(ava_id)
  def get_session_user(_session), do: {:error, :not_authenticated}

  # Revalida a cada request/mount: uma conta desativada pelo zelador deixa de
  # resolver, então a sessão ainda aberta cai no próximo acesso -- honra o
  # "não vai mais conseguir entrar" da tela de membros. Consulta de sistema:
  # roda antes de haver contexto, no request que o próprio contexto constrói.
  defp resolve_session_ava(public_id) when is_binary(public_id) do
    Repo.with_system(fn ->
      case Repo.get_by(Ava, [public_id: public_id], skip_tekoa_id: true) do
        %Ava{deactivated_at: nil} = ava ->
          ## Gestão de membros (zelador)
          tekoa = Repo.get!(Tekoa, ava.tekoa_id, skip_tekoa_id: true)
          {:ok, %{ava | tekoa: tekoa}}

        _ ->
          {:error, :not_authenticated}
      end
    end)
  end

  defp resolve_session_ava(_public_id), do: {:error, :not_authenticated}

  def update_tekoa_quota(%Ypy.Scope{} = scope, quota_bytes) when is_integer(quota_bytes) do
    if zelador?(scope.ava) do
      result = within_tekoa(scope, fn -> mudar_cota(scope, quota_bytes) end)

      with {:ok, _tekoa} <- result do
        record_event(scope, :quota_changed, %{
          "from" => scope.tekoa.storage_quota_bytes,
          "to" => quota_bytes
        })
      end

      result
    else
      {:error, :unauthorized}
    end
  end

  defp mudar_cota(%Ypy.Scope{} = scope, quota_bytes) do
    case KernelStore.get_tekoa(Repo, scope.tekoa.id) do
      %Tekoa{} = tekoa -> Repo.update(Tekoa.changeset(tekoa, %{storage_quota_bytes: quota_bytes}))
      nil -> {:error, :not_found}
    end
  end

  @doc """
  A troca de papel e verbo do kernel (`Ypy.Maraca.mudar_papel/5`): guarda de
  zelador, protecao da ultima zeladoria e a entrada na cadeia sao dela.
  """
  def update_member_role(%Ypy.Scope{} = scope, member_public_id, papel) do
    within_tekoa(scope, fn ->
      with {:ok, member} <- fetch_member(scope, member_public_id) do
        Ypy.Maraca.mudar_papel(Repo, Keys.new(), scope, member, papel)
      end
    end)
  end

  @doc "Desativar e fluxo do produto: o kernel guarda o substantivo, aqui o rito."
  def deactivate_member(%Ypy.Scope{} = scope, member_public_id) do
    with :ok <- ensure_zelador(scope) do
      result = within_tekoa(scope, fn -> do_deactivate(scope, member_public_id) end)

      with {:ok, member} <- result do
        record_event(scope, :member_deactivated, %{"member" => ava_name(member)})
      end

      result
    end
  end

  def reactivate_member(%Ypy.Scope{} = scope, member_public_id) do
    with :ok <- ensure_zelador(scope) do
      result = within_tekoa(scope, fn -> do_reactivate(scope, member_public_id) end)

      with {:ok, member} <- result do
        record_event(scope, :member_reactivated, %{"member" => ava_name(member)})
      end

      result
    end
  end

  def revoke_invite(%Ypy.Scope{} = scope, member_public_id) do
    with :ok <- ensure_zelador(scope) do
      result = within_tekoa(scope, fn -> do_revoke_invite(scope, member_public_id) end)

      with {:ok, member} <- result do
        record_event(scope, :invite_revoked, %{"role" => Atom.to_string(member.papel)})
      end

      result
    end
  end

  defp do_revoke_invite(scope, public_id) do
    with {:ok, member} <- fetch_member(scope, public_id),
         :ok <- ensure_pending_invite(member) do
      # O convite pendente não tem identidade nem dados (nada aponta para ele),
      # então revogar apaga a linha. Um soft-delete deixaria um "morador" sem
      # nome na lista para sempre.
      Repo.delete(member)
    end
  end

  # Só convite ainda não aceito é revogável. Conta já ativada se remove com
  # desativar (soft): apagar a linha levaria as concessões e os pedidos junto
  # e sumiria com o histórico.
  defp ensure_pending_invite(%Ava{activated_at: nil}), do: :ok
  defp ensure_pending_invite(%Ava{}), do: {:error, :not_pending}

  defp ensure_zelador(%Ypy.Scope{ava: ava}) do
    if zelador?(ava), do: :ok, else: {:error, :unauthorized}
  end

  defp do_deactivate(scope, public_id) do
    with {:ok, member} <- fetch_member(scope, public_id) do
      deactivate_if_allowed(scope, member)
    end
  end

  defp do_reactivate(scope, public_id) do
    with {:ok, member} <- fetch_member(scope, public_id) do
      Repo.update(Ava.deactivation_changeset(member, nil))
    end
  end

  defp fetch_member(scope, public_id) do
    # O public_id do kernel e estrito (12 caracteres do alfabeto): id
    # malformado de URL/params nao chega a ser query, responde not_found.
    ## Reset de senha
    if PublicId.valid?(public_id) do
      case Repo.get_by(Ava, public_id: public_id, tekoa_id: scope.tekoa.id) do
        nil -> {:error, :not_found}
        %Ava{} = ava -> {:ok, ava}
      end
    else
      {:error, :not_found}
    end
  end

  # Idempotente: conta já desativada não muda. O último zelador ativo não pode
  # ser desativado (a comunidade ficaria sem quem cuida da máquina).
  defp deactivate_if_allowed(_scope, %Ava{deactivated_at: at} = member) when not is_nil(at) do
    {:ok, member}
  end

  defp deactivate_if_allowed(scope, %Ava{} = member) do
    if last_active_zelador?(scope, member) do
      {:error, :last_zelador}
    else
      Repo.update(Ava.deactivation_changeset(member, agora()))
    end
  end

  defp last_active_zelador?(_scope, %Ava{papel: papel, deactivated_at: deactivated_at})
       when papel != :zelador or not is_nil(deactivated_at), do: false

  defp last_active_zelador?(scope, %Ava{}), do: active_zelador_count(scope) == 1

  # Serialização de desativações e rebaixamentos concorrentes: no Postgres o
  # `FOR UPDATE` travava as linhas dos zeladores ativos. O SQLite não tem row
  # lock; a escrita inteira da caixa é serializada pelo lock do arquivo (com
  # `busy_timeout`, o segundo bloqueia, relê após o commit do primeiro e
  # enxerga o count atualizado). Roda sempre dentro do contexto de Tekoa. Só
  # conta zelador já ativado: um convite pendente de zelador não é gente ainda.
  defp active_zelador_count(scope) do
    from(a in Ava,
      where:
        a.tekoa_id == ^scope.tekoa.id and a.papel == :zelador and
          is_nil(a.deactivated_at) and not is_nil(a.activated_at),
      select: a.id
    )
    |> Repo.all()
    |> length()
  end

  @doc """
  O zelador gera o link de redefinicao de um morador: o token cru volta para
  o chamador montar a URL (a entrega e o canal sao do produto).
  """
  def mint_reset_link(%Ypy.Scope{} = scope, %Ava{} = member) do
    ## Verbos sociais do kernel (concessao, pedido, decisao)
    if zelador?(scope.ava) do
      mint_reset_link_zelador(scope, member)
    else
      {:error, :unauthorized}
    end
  end

  defp mint_reset_link_zelador(%Ypy.Scope{} = scope, %Ava{} = member) do
    raw_token = generate_token()

    with {:ok, %{ava: with_token, token: token}} <-
           within_tekoa(scope, fn -> mint_reset_token(scope, member, raw_token) end) do
      record_event(scope, :reset_link_created, %{"member" => ava_name(with_token)})
      {:ok, %{ava: with_token, token: token}}
    end
  end

  defp mint_reset_token(%Ypy.Scope{} = scope, %Ava{} = member, raw_token) do
    case Repo.get_by(Ava, public_id: member.public_id, tekoa_id: scope.tekoa.id) do
      nil ->
        {:error, :not_found}

      %Ava{} = ava ->
        Repo.update(
          Ava.reset_request_changeset(ava, %{
            reset_token_hash: hash_token(raw_token),
            reset_sent_at: agora()
          })
        )

        {:ok, %{ava: ava, token: raw_token}}
    end
  end

  def reset_password(reset_token, new_password, password_confirmation) do
    with %Ava{} = ava <- find_by_token(:reset_token_hash, reset_token),
         false <- token_expired?(ava.reset_sent_at, @reset_max_age_seconds),
         :ok <-
           confirmation_ok?(%{password: new_password, password_confirmation: password_confirmation}),
         {:ok, _ava} = result <-
           Repo.with_tekoa(tekoa_public_id(ava), fn ->
             Repo.update(Ava.reset_changeset(ava, %{password: new_password}))
           end) do
      # Trocou a senha no caminho do reset, derruba os aparelhos: quem pediu
      # o reset nao tem aparelho de chamada (o link veio do zelador ou do
      # shell), entao todos caem.
      revoke_other_devices(reset_scope(ava), except: nil)
      result
    else
      # O changeset da senha nova segue do jeito que era: a tela do reset
      # aponta o campo (aqui nao existe "senha curta vira link invalido").
      {:error, %Ecto.Changeset{}} = changeset ->
        changeset

      # As duas senhas não batem: é erro do formulário, não link vencido.
      {:error, :password_mismatch} ->
        {:error, :password_mismatch}

      _ ->
        {:error, :invalid_token}
    end
  end

  # O scope da conta que resetou: a Tekoa vem do id, fora do contexto (a
  # revogacao abre o proprio `with_tekoa/2`).
  defp reset_scope(%Ava{} = ava) do
    {:ok, tekoa} =
      Repo.with_system(fn -> {:ok, Repo.get!(Tekoa, ava.tekoa_id, skip_tekoa_id: true)} end)

    Scope.new(ava, tekoa)
  end

  @doc """
  Status de um link de reset pelo token cru, sem consumir: `:ok` enquanto o
  link vale, `:invalid` quando expirou ou não existe. Mesma intenção do
  `invite_status/1` para a tela de redefinir senha.
  """
  def reset_status(token) do
    case find_by_token(:reset_token_hash, token) do
      %Ava{} = ava ->
        if token_expired?(ava.reset_sent_at, @reset_max_age_seconds), do: :invalid, else: :ok

      _ ->
        :invalid
    end
  end

  @doc """
  A troca da propria senha (self-service): confere a senha atual pelo mesmo
  caminho do login (bcrypt, com o MESMO rate limit de forca bruta) e grava a
  nova pelo changeset do kernel, que valida, hashea e queima qualquer link de
  reset pendente. Nao revoga aparelhos: quem sabe qual aparelho fez a chamada
  (o endpoint da API) que cuide dos outros, com `revoke_other_devices/2`.
  """
  @spec update_password(Ypy.Scope.t(), String.t(), String.t()) ::
          {:ok, Ava.t()}
          | {:error, :invalid_credentials | :rate_limited | Ecto.Changeset.t()}
  def update_password(%Ypy.Scope{} = scope, current_password, new_password) do
    key = login_rate_key(scope.tekoa, scope.ava.username)

    if login_rate_exceeded?(key) do
      {:error, :rate_limited}
    else
      change_password(scope, current_password, new_password, key)
    end
  end

  defp change_password(%Ypy.Scope{} = scope, current_password, new_password, key) do
    within_tekoa(scope, fn ->
      with {:ok, ava} <- fetch_member(scope, scope.ava.public_id),
           :ok <- current_password_ok?(ava, current_password, key) do
        new_password_changeset(ava, new_password)
      end
    end)
  end

  # Falha de credencial e um erro so: quem troca a propria senha nao distingue
  # "senha errada" de conta desativada (conta desativada nem chega logada). A
  # conferencia errada queima a janela do login, como um login errado.
  defp current_password_ok?(ava, current_password, key) do
    case verify_credentials(ava, current_password) do
      {:ok, _ava} -> :ok
      {:error, _reason} -> record_login_failure(key, {:error, :invalid_credentials})
    end
  end

  # A senha nova segue pelo changeset do kernel. Cliente baguncado (JSON sem
  # tipo) nao chega ao Ecto com valor que nao e texto: volta no mesmo
  # contrato de uma senha que viola a regra (changeset com erro no campo).
  defp new_password_changeset(%Ava{} = ava, password) when is_binary(password) do
    Repo.update(Ava.reset_changeset(ava, %{password: password}))
  end

  defp new_password_changeset(%Ava{} = ava, _password) do
    {:error, ava |> Ava.reset_changeset(%{}) |> Ecto.Changeset.add_error(:password, "is invalid")}
  end

  @doc """
  Trocou a senha, derrubou os aparelhos: revoga os tokens de dispositivo de
  quem esta agindo, menos o da chamada (`except:`) -- web e shell nao tem
  aparelho de chamada, entao chamam com `except: nil`, que derruba todos.
  Best-effort, como o logout: um aparelho que sumiu da mesa (expurgo, corrida
  concorrente) nao derruba a troca de senha, o token dele ja nao vale nada.
  """
  @spec revoke_other_devices(Ypy.Scope.t(), keyword()) :: :ok
  def revoke_other_devices(%Ypy.Scope{} = scope, opts \\ []) do
    except = Keyword.get(opts, :except)
    {:ok, devices} = list_devices(scope)

    devices
    |> Enum.reject(&(&1.public_id == except))
    |> Enum.each(fn device -> _ = revoke_device(scope, device.public_id) end)

    :ok
  end

  @doc """
  Pode `ava` agir sobre o recurso? A leitura segue a regra das duas zonas do
  kernel (praca OU dono OU concessao, RFC_003 D2); escrever e apagar sao do
  dono (a concessao do kernel e sempre de leitura).
  """
  def authorize?(%Ava{} = ava, action, tipo, rkey)
      when is_atom(action) and is_binary(tipo) and is_binary(rkey) and tipo in @kernel_tipos do
    {:ok, authorized?} =
      Repo.with_tekoa(tekoa_public_id(ava), fn ->
        scope = Scope.new(ava, Repo.get!(Tekoa, ava.tekoa_id))

        {:ok,
         cond do
           action == :read -> Ypy.Ybira.readable?(Repo, scope, tipo, rkey)
           Ypy.Ybira.owner?(Repo, scope.tekoa.id, tipo, rkey, ava.id) -> true
           true -> false
         end}
      end)

    authorized?
  end

  def authorize?(_ava, _action, _tipo, _rkey), do: false

  def authorize!(%Ava{} = ava, action, tipo, rkey) do
    if authorize?(ava, action, tipo, rkey) do
      :ok
    else
      raise Taina.Maraca.UnauthorizedError,
        ava: ava,
        action: action,
        resource_type: tipo,
        resource_id: rkey
    end
  end

  @doc """
  A regra de leitura sobre um recurso resolvido pelo rkey, delegada ao kernel
  (`Ypy.Ybira.readable?/4`): casa alheia sem concessao nao passa, e o zelador
  nao tem atalho.
  """
  @spec can_read?(Ypy.Scope.t(), String.t(), String.t()) :: boolean()
  def can_read?(%Ypy.Scope{} = scope, tipo, rkey) when tipo in @kernel_tipos do
    Ypy.Ybira.readable?(Repo, scope, tipo, rkey)
  end

  ## Mural (a projecao da cadeia, RFC_006 secao 8)

  @doc "Abre a propria casa para um leitor (kernel: `Ypy.Maraca.conceder/6`)."
  def conceder(%Ypy.Scope{} = scope, tipo, rkey, %Ava{} = leitor) do
    within_tekoa(scope, fn ->
      Ypy.Maraca.conceder(Repo, Keys.new(), scope, tipo, rkey, leitor)
    end)
  end

  @doc "Revoga a concessao ativa (kernel: `Ypy.Maraca.revogar/4`)."
  def revogar(%Ypy.Scope{} = scope, %Concessao{} = concessao) do
    within_tekoa(scope, fn ->
      # Rele antes de revogar: o estado pode ter mudado desde o struct em
      # maos (revogada em outra janela), e o guard do kernel julga o atual.
      case KernelStore.get_concessao(Repo, scope.tekoa.id, concessao.id) do
        nil -> {:error, :not_found}
        %Concessao{} = atual -> Ypy.Maraca.revogar(Repo, Keys.new(), scope, atual)
      end
    end)
  end

  @doc """
  O pedido de acesso (kernel: `Ypy.Maraca.pedir_acesso/5`) mais a notificacao
  do produto: o dono ouve no PubSub para a tela dele acender o aviso.
  """
  def pedir_acesso(%Ypy.Scope{} = scope, tipo, rkey, motivo) do
    with {:ok, %{pedido: pedido, dono_pid: dono_pid}} <-
           within_tekoa(scope, fn -> pedir_acesso_na_tekoa(scope, tipo, rkey, motivo) end) do
      notify(dono_pid, {:access_requested, pedido})
      {:ok, pedido}
    end
  end

  defp pedir_acesso_na_tekoa(%Ypy.Scope{} = scope, tipo, rkey, motivo) do
    with {:ok, pedido} <- Ypy.Maraca.pedir_acesso(Repo, scope, tipo, rkey, motivo) do
      {:ok, %{pedido: pedido, dono_pid: ava_public_id(scope.tekoa.id, pedido.dono_id)}}
    end
  end

  @doc "Aprova o pedido pendente; nasce a concessao, entrada na cadeia."
  def aprovar(%Ypy.Scope{} = scope, %Pedido{} = pedido) do
    with {:ok, %{concessao: concessao, pedinte_pid: pedinte_pid}} <-
           within_tekoa(scope, fn -> aprovar_na_tekoa(scope, pedido) end) do
      notify(pedinte_pid, {:access_request_approved, concessao})
      {:ok, concessao}
    end
  end

  defp aprovar_na_tekoa(%Ypy.Scope{} = scope, %Pedido{} = pedido) do
    with {:ok, %{pedido: pedido, concessao: concessao}} <-
           Ypy.Maraca.aprovar(Repo, Keys.new(), scope, pedido) do
      {:ok, %{concessao: concessao, pedinte_pid: ava_public_id(scope.tekoa.id, pedido.pedinte_id)}}
    end
  end

  @doc "Nega o pedido pendente. Nada muda de visibilidade, o pedido registra."
  def negar(%Ypy.Scope{} = scope, %Pedido{} = pedido) do
    with {:ok, %{pedido: pedido, pedinte_pid: pedinte_pid}} <-
           within_tekoa(scope, fn -> negar_na_tekoa(scope, pedido) end) do
      notify(pedinte_pid, {:access_request_denied, pedido})
      {:ok, pedido}
    end
  end

  defp negar_na_tekoa(%Ypy.Scope{} = scope, %Pedido{} = pedido) do
    with {:ok, pedido} <- Ypy.Maraca.negar(Repo, scope, pedido) do
      {:ok, %{pedido: pedido, pedinte_pid: ava_public_id(scope.tekoa.id, pedido.pedinte_id)}}
    end
  end

  @doc "Os pedidos pendentes que o morador recebeu como dono (com quem pediu)."
  def pedidos_recebidos(%Ypy.Scope{} = scope) do
    within_tekoa(scope, fn ->
      {:ok, Repo |> Ypy.Maraca.pedidos_recebidos(scope) |> Repo.preload(:pedinte)}
    end)
  end

  @doc """
  Os pedidos ainda sem decisao que o morador fez (com o dono de quem espera).
  Os ja decididos saem daqui para a secao "Ja decididos" da tela de Pedidos
  (`list_my_recent_decisions/1`) e nao voltam como pendentes: o kernel lista de
  todos os status, o produto separa as secoes da tela.
  """
  def pedidos_enviados(%Ypy.Scope{} = scope) do
    within_tekoa(scope, fn ->
      pedidos =
        Repo
        |> Ypy.Maraca.pedidos_enviados(scope)
        |> Repo.preload(:dono)
        |> Enum.filter(&(&1.status == :pendente))

      {:ok, pedidos}
    end)
  end

  @doc """
  As concessoes ainda em pe que o morador concedeu (com o leitor): as da
  secao "Ja liberados". Revogadas saem da tela (o rito delas fica registrado
  na cadeia; o kernel lista de todos os status).
  """
  def concessoes_concedidas(%Ypy.Scope{} = scope) do
    within_tekoa(scope, fn ->
      concessoes =
        Repo
        |> Ypy.Maraca.concessoes_concedidas(scope)
        |> Enum.reject(& &1.revogada_em)
        |> Repo.preload(:leitor)

      {:ok, concessoes}
    end)
  end

  @doc """
  Pedidos feitos por `scope.ava` já decididos (aprovados ou recusados), para a
  seção "Já decididos" da tela de Pedidos não deixar o pedido sumir sem
  explicação (RFC_003: sem resultado silencioso). Ordena pela última decisão.
  """
  def list_my_recent_decisions(%Ypy.Scope{} = scope) do
    within_tekoa(scope, fn ->
      decisions =
        from(p in Pedido,
          where: p.tekoa_id == ^scope.tekoa.id,
          where: p.pedinte_id == ^scope.ava.id,
          where: p.status != :pendente,
          order_by: [desc: p.decidido_em]
        )
        |> Repo.all()
        |> Repo.preload(:dono)

      {:ok, decisions}
    end)
  end

  def subscribe_to_my_events(%Ava{public_id: pid}) do
    Phoenix.PubSub.subscribe(Taina.PubSub, "maraca:ava:" <> pid)
  end

  @doc """
  Registra o ato do produto (convite, desativacao, cota...) como entrada da
  cadeia unica, assinada pela chave da Tekoa. O ato ja aconteceu: falha de
  cadeia vira log, nunca derruba quem chamou. Verbos do kernel (concessao,
  publicar, mudar papel...) anexam a propria entrada, sem passar daqui.
  """
  def record_event(%Ypy.Scope{} = scope, type, payload) when is_map(payload) do
    result =
      within_tekoa(scope, fn ->
        MuralStore.append(
          Repo,
          Keys.new(),
          scope.tekoa.id,
          to_string(type),
          Map.put(payload, "actor", scope.ava.public_id)
        )
      end)

    case result do
      {:ok, _entry} ->
        # Camada 3 da transparência (RFC_003 seção 6): métrica na caixa, sem
        # reporter para fora. O tipo no metadata, nunca ids de tekoa/ava.
        :telemetry.execute([:taina, :maraca, :event], %{count: 1}, %{type: type})
        :ok

      {:error, reason} ->
        ## Helpers internos
        Logger.warning("Mural: falha ao registrar evento (o ato já aconteceu), #{inspect(type)}",
          reason: inspect(reason)
        )

        :ok
    end
  rescue
    e ->
      Logger.warning("Mural: exceção ao registrar evento (o ato já aconteceu), #{inspect(type)}",
        reason: inspect(e)
      )

      :ok
  end

  @doc """
  A projecao legivel do mural: as entradas da cadeia, da mais recente para a
  mais antiga, com paginação por offset. O `payload` de cada entrada traz o
  que a frase precisa (o ator vem em `"actor"`).
  """
  def list_events(%Ypy.Scope{} = scope, opts \\ []) do
    limit = Keyword.get(opts, :limit, @event_page_limit)
    offset = Keyword.get(opts, :offset, 0)

    within_tekoa(scope, fn ->
      query =
        from(e in Ypy.Mural.Entry,
          where: e.tekoa_id == ^scope.tekoa.id,
          order_by: [desc: e.seq]
        )

      rows =
        query
        |> limit(^(limit + 1))
        |> offset(^offset)
        |> Repo.all()

      if length(rows) > limit do
        {:ok, %{events: Enum.take(rows, limit), next_offset: offset + limit}}
      else
        {:ok, %{events: rows, next_offset: nil}}
      end
    end)
  end

  ## Dispositivos (RFC_005 secao 4)

  # O carimbo de uso so vale a pena a cada janela: sem escrita no caminho quente.
  @device_last_used_window_seconds 5 * 60

  @doc """
  Cria um token de dispositivo para quem esta agindo: o irmao mobile da sessao
  Phoenix. O segredo cru (`tnd_` mais 32 caracteres) volta uma unica vez, para
  o cliente guardar; no banco fica so o hash. Sem evento no mural: entrar no
  proprio celular e higiene de conta, como trocar a senha.
  """
  def create_device_token(%Ypy.Scope{} = scope, name) do
    raw_token = "tnd_" <> generate_token()

    device =
      %DeviceToken{}
      |> DeviceToken.changeset(%{name: name})
      |> Ecto.Changeset.change(%{
        token_hash: hash_token(raw_token),
        ava_id: scope.ava.id,
        tekoa_id: scope.tekoa.id
      })

    within_tekoa(scope, fn ->
      case Repo.insert(device) do
        {:ok, device} -> {:ok, %{device: device, token: raw_token}}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  @doc """
  Resolve o segredo cru de um dispositivo no contexto da requisicao. Consulta
  de sistema: o token e justamente o que constroi o contexto. Revalida a conta
  a cada chamada (conta desativada nao resolve, mesmo com o token intacto),
  igual a sessao web.
  """
  def resolve_device_token(token) when is_binary(token) do
    token_hash = hash_token(token)

    {:ok, device} =
      Repo.with_system(fn -> {:ok, load_device(token_hash)} end)

    case active_device(device) do
      {:ok, device} ->
        device = touch_last_used(device)
        {:ok, %{scope: Scope.new(device.ava, device.tekoa), device: device}}

      :error ->
        {:error, :not_authenticated}
    end
  end

  def resolve_device_token(_token), do: {:error, :not_authenticated}

  # Consulta de sistema: busca o dispositivo pelo hash e carrega a conta e a
  # Tekoa explicitamente (o preload nao aceita skip_tekoa_id).
  defp load_device(token_hash) do
    case Repo.get_by(DeviceToken, [token_hash: token_hash], skip_tekoa_id: true) do
      nil ->
        nil

      device ->
        ava = Repo.get(Ava, device.ava_id, skip_tekoa_id: true)
        tekoa = Repo.get(Tekoa, device.tekoa_id, skip_tekoa_id: true)
        %{device | ava: ava, tekoa: tekoa}
    end
  end

  @doc """
  Os dispositivos de quem esta agindo, do mais recente para o mais antigo. A
  listagem e da propria pessoa: a zeladora revoga o dispositivo de outra, mas
  nao ve a lista dela.
  """
  def list_devices(%Ypy.Scope{} = scope) do
    within_tekoa(scope, fn ->
      devices =
        from(d in DeviceToken,
          where: d.tekoa_id == ^scope.tekoa.id and d.ava_id == ^scope.ava.id,
          order_by: [desc: d.inserted_at, desc: d.id]
        )

      {:ok, Repo.all(devices)}
    end)
  end

  @doc """
  Revoga um dispositivo pela dona ou pela zeladora. Idempotente: revogar de
  novo devolve o mesmo dispositivo, sem erro.
  """
  def revoke_device(%Ypy.Scope{} = scope, device_public_id) do
    if PublicId.valid?(device_public_id) do
      revoke_known_device(scope, device_public_id)
    else
      {:error, :not_found}
    end
  end

  defp revoke_known_device(%Ypy.Scope{} = scope, device_public_id) do
    within_tekoa(scope, fn ->
      case Repo.get_by(DeviceToken, public_id: device_public_id, tekoa_id: scope.tekoa.id) do
        nil -> {:error, :not_found}
        %DeviceToken{} = device -> revoke_allowed(scope, device)
      end
    end)
  end

  defp revoke_allowed(%Ypy.Scope{} = scope, %DeviceToken{ava_id: ava_id} = device) do
    if ava_id == scope.ava.id or zelador?(scope.ava) do
      {:ok, revoke(device)}
    else
      {:error, :unauthorized}
    end
  end

  defp active_device(%DeviceToken{revoked_at: nil, ava: %Ava{} = ava} = device) do
    if ava.activated_at != nil and ava.deactivated_at == nil do
      {:ok, device}
    else
      :error
    end
  end

  defp active_device(_device), do: :error

  defp touch_last_used(%DeviceToken{last_used_at: at} = device) do
    if stale_usage?(at), do: stamp_usage(device), else: device
  end

  # O carimbo e auxiliar: se a escrita falhar, a autenticacao segue com o
  # dispositivo ja lido, em vez de derrubar uma requisicao valida.
  defp stamp_usage(%DeviceToken{} = device) do
    result =
      Repo.with_tekoa(device.tekoa.public_id, fn ->
        device
        |> Ecto.Changeset.change(last_used_at: agora())
        |> Repo.update()
      end)

    case result do
      {:ok, updated} -> updated
      {:error, _changeset} -> device
    end
  end

  defp stale_usage?(nil), do: true

  defp stale_usage?(%DateTime{} = at) do
    DateTime.diff(agora(), at) >= @device_last_used_window_seconds
  end

  defp revoke(%DeviceToken{revoked_at: %DateTime{}} = device), do: device

  defp revoke(%DeviceToken{} = device) do
    {:ok, revoked} =
      device
      |> Ecto.Changeset.change(revoked_at: agora())
      |> Repo.update()

    revoked
  end

  ## Buscas por id publico (RFC_005 secao 9)

  @doc "Um morador pelo id publico, dentro da Tekoa."
  def get_member(%Ypy.Scope{} = scope, member_public_id) do
    within_tekoa(scope, fn -> fetch_member(scope, member_public_id) end)
  end

  @doc "Um pedido de acesso pelo id publico, dentro da Tekoa."
  def get_pedido(%Ypy.Scope{} = scope, pedido_public_id) do
    if PublicId.valid?(pedido_public_id) do
      within_tekoa(scope, fn -> fetch_pedido(scope, pedido_public_id) end)
    else
      {:error, :not_found}
    end
  end

  defp fetch_pedido(%Ypy.Scope{} = scope, pedido_public_id) do
    case Repo.get_by(Pedido, public_id: pedido_public_id, tekoa_id: scope.tekoa.id) do
      nil -> {:error, :not_found}
      %Pedido{} = pedido -> {:ok, pedido}
    end
  end

  ## Predicados

  # O predicado puro e do kernel (`Ypy.Maraca.Policy`); aqui so extrai o papel.
  def zelador?(%Ava{papel: papel}), do: Policy.zelador?(papel)

  def morador?(%Ava{papel: papel}), do: Policy.morador?(papel)

  def activated?(%Ava{} = ava), do: Ava.active?(ava)

  defp within_tekoa(%Ypy.Scope{} = scope, cb), do: Repo.with_tekoa(scope.tekoa.public_id, cb)

  defp ava_public_id(tekoa_id, ava_id) do
    case KernelStore.get_ava(Repo, tekoa_id, ava_id) do
      %Ava{public_id: public_id} -> public_id
      nil -> nil
    end
  end

  # Nome social do Ava para as frases do mural: nome de exibição quando existe,
  # senão o nome de usuário. Convite pendente (sem nome ainda) cai em nil e o
  # mural decide o que mostrar.
  defp ava_name(%Ava{} = ava), do: ava.display_name || ava.username
  defp ava_name(_other), do: nil

  defp find_by_token(hash_field, token) when is_binary(token) do
    # Consulta de sistema: usada no aceite/reset, antes de haver contexto --
    # a busca é justamente o que constrói o contexto.
    {:ok, ava} =
      Repo.with_system(fn ->
        {:ok, Repo.get_by(Ava, [{hash_field, hash_token(token)}], skip_tekoa_id: true)}
      end)

    ava
  end

  defp find_by_token(_hash_field, _token), do: nil

  defp token_expired?(nil, _max_age), do: true

  defp token_expired?(%DateTime{} = sent_at, max_age_seconds) do
    DateTime.diff(DateTime.utc_now(), sent_at) > max_age_seconds
  end

  defp tekoa_public_id(%Ava{tekoa: %Tekoa{public_id: public_id}}), do: public_id

  defp tekoa_public_id(%Ava{tekoa_id: tekoa_id}) do
    # Consulta de sistema: resolve o public_id da Tekoa antes de abrir o
    # contexto (o contexto é justamente este public_id).
    {:ok, public_id} =
      Repo.with_system(fn ->
        {:ok, Repo.get!(Tekoa, tekoa_id, skip_tekoa_id: true).public_id}
      end)

    public_id
  end

  defp notify(nil, _message), do: :ok

  defp notify(ava_public_id, message) do
    Phoenix.PubSub.broadcast(Taina.PubSub, "maraca:ava:" <> ava_public_id, message)
  end

  defp generate_token, do: Nanoid.generate(32)

  # Hash SHA256 do token cru, o mesmo formato consultado por find_by_token/2.
  defp hash_token(raw_token) do
    :sha256 |> :crypto.hash(raw_token) |> Base.encode64(padding: false)
  end

  defp fetch_attr(attrs, key) when is_map(attrs), do: Map.get(attrs, key) || Map.get(attrs, to_string(key))

  defp agora, do: DateTime.truncate(DateTime.utc_now(), :second)
end
