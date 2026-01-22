defmodule Taina.Maraca.AccessRequest do
  @moduledoc """
  Representa uma solicitação de acesso de um administrador a um recurso de usuário.

  Este schema é fundamental para a filosofia do Tainá: **administradores são facilitadores,
  não deuses**. Ao contrário de sistemas tradicionais onde admins têm acesso irrestrito,
  no Tainá eles devem solicitar permissão explícita do dono do recurso.

  ## Filosofia e fluxo

  1. **Admin tenta acessar** - Sistema nega acesso (não possui Permission)
  2. **Admin solicita acesso** - Cria AccessRequest com justificativa
  3. **Dono é notificado** - Recebe solicitação via PubSub/email
  4. **Dono decide** - Aprova (cria Permission temporária) ou nega
  5. **Rastreabilidade** - Todas as solicitações ficam registradas

  ## Campos principais

    * `requester_id` - ID do Ava que solicita acesso (geralmente um admin)
    * `owner_id` - ID do Ava dono do recurso (quem pode aprovar/negar)
    * `resource_type` - Tipo do recurso (ex: "ybira_file", "guara_chat")
    * `resource_id` - ID público do recurso específico
    * `reason` - Justificativa da solicitação (ex: "Ticket de suporte #123")
    * `status` - Estado atual: :pending, :approved, ou :denied
    * `tekoa_id` - Comunidade onde a solicitação ocorre

  ## Estados do fluxo

    * `:pending` - Aguardando decisão do dono
    * `:approved` - Dono concedeu acesso (cria Permission automaticamente)
    * `:denied` - Dono negou acesso

  ## Exemplos de uso

      # Admin solicita acesso a arquivo de usuário
      iex> changeset(%AccessRequest{}, %{
      ...>   requester_id: admin.id,
      ...>   owner_id: user.id,
      ...>   resource_type: "ybira_file",
      ...>   resource_id: file.public_id,
      ...>   reason: "Investigação de bug reportado no ticket #456",
      ...>   tekoa_id: tekoa.id
      ...> })
      %Ecto.Changeset{valid?: true}

      # Solicitação sem justificativa é inválida
      iex> changeset(%AccessRequest{}, %{reason: nil})
      %Ecto.Changeset{valid?: false}

  ## Segurança

  Esta tabela possui Row-Level Security (RLS) habilitado. Apenas solicitações da
  Tekoa atual são visíveis através do contexto `app.current_tekoa_id`.

  ## Privacidade e transparência

  Todas as solicitações são permanentemente registradas para auditoria. Isso garante:
  - Transparência sobre quem acessou dados de quem
  - Rastreabilidade para compliance (LGPD, GDPR)
  - Confiança entre usuários e administradores
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Taina.Maraca

  @statuses ~w(pending approved denied)a

  @schema_prefix "maraca"
  schema "access_requests" do
    field :reason, :string
    field :resource_id, :string
    field :resource_type, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending

    belongs_to :owner, Maraca.Ava
    belongs_to :requester, Maraca.Ava
    belongs_to :tekoa, Maraca.Tekoa

    timestamps()
  end

  @doc """
  Valida uma AccessRequest com as informações fornecidas.

  ## Campos obrigatórios

    * `requester_id` - Ava que está solicitando acesso
    * `owner_id` - Ava dono do recurso (quem pode aprovar)
      * `resource_type` - Tipo do recurso (ex: "ybira_file")
    * `resource_id` - ID público do recurso
    * `reason` - Justificativa da solicitação (máximo 250 caracteres)
    * `tekoa_id` - Comunidade onde a solicitação ocorre

  ## Validações

    * `reason` deve ter no máximo 250 caracteres
    * `status` deve estar na lista: #{inspect(@statuses)}
    * `requester_id` e `owner_id` devem ser diferentes (não pode solicitar acesso a próprio recurso)

  ## Exemplos

      iex> changeset(%AccessRequest{}, %{
      ...>   requester_id: admin.id,
      ...>   owner_id: user.id,
      ...>   resource_type: "ybira_file",
      ...>   resource_id: file.public_id,
      ...>   reason: "Suporte ticket #123",
      ...>   tekoa_id: tekoa.id
      ...> })
      %Ecto.Changeset{valid?: true}

      iex> changeset(%AccessRequest{}, %{reason: String.duplicate("a", 300)})
      %Ecto.Changeset{valid?: false}
  """
  def changeset(%__MODULE__{} = request, %{} = attrs) do
    request
    |> cast(attrs, [:reason, :resource_id, :resource_type, :status, :owner_id, :requester_id, :tekoa_id])
    |> validate_required([:reason, :resource_id, :resource_type, :status, :owner_id, :requester_id, :tekoa_id])
    |> validate_length(:reason, max: 250)
    |> validate_different_avas()
  end

  defp validate_different_avas(changeset) do
    requester_id = get_field(changeset, :requester_id)
    owner_id = get_field(changeset, :owner_id)

    if requester_id && owner_id && requester_id == owner_id do
      add_error(changeset, :requester_id, "não pode solicitar acesso ao próprio recurso")
    else
      changeset
    end
  end
end
