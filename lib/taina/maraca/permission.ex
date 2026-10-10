defmodule Taina.Maraca.Permission do
  @moduledoc """
  Representa uma permissão explícita concedida a um Ava para acessar um recurso específico.

  No Tainá, seguimos o princípio de que **os usuários são donos de seus dados**. Isso significa
  que permissões devem ser explícitas - nenhum acesso é concedido automaticamente, nem mesmo
  para o zelador. Cada Permission registra quem pode fazer o quê com qual recurso.

  ## Filosofia

  Diferente de sistemas tradicionais onde quem administra tem acesso irrestrito, no Tainá:
  - Proprietários de recursos controlam totalmente o acesso
  - O zelador deve solicitar permissão via AccessRequest
  - Todas as permissões são rastreáveis e revogáveis

  ## Campos principais

    * `ava_id` - ID do Ava que recebe a permissão
    * `resource_type` - Tipo do recurso (ex: "ybira_file", "ybira_folder", "guara_chat")
    * `resource_id` - ID público do recurso específico
    * `action` - Ação permitida: :read, :write, ou :delete
    * `granted_by_id` - ID do Ava que concedeu a permissão (rastreabilidade)
    * `tekoa_id` - Comunidade à qual a permissão pertence (isolamento RLS)

  ## Ordem de resolução de permissões

  1. **Isolamento de comunidade** - RLS garante que apenas recursos da mesma Tekoa sejam visíveis
  2. **Propriedade do recurso** - Donos têm acesso total automaticamente
  3. **Permissões explícitas** - Verificadas nesta tabela
  4. **Negação padrão** - Se nada acima se aplicar, acesso negado

  ## Uso correto (anti-spoofing)

  `grant_changeset/2` é o único construtor de Permission. `granted_by_id` e
  `tekoa_id` são aceitos no cast porque o attrs é construído pelo serviço a
  partir de valores de confiança (o scope autenticado), nunca de parâmetros
  externos. Ambos são obrigatórios, então a trilha de auditoria nunca nasce
  pela metade:

      # Usuário A compartilha arquivo com Usuário B (leitura)
      %Permission{}
      |> Permission.grant_changeset(%{
        ava_id: user_b.id,
        resource_type: "ybira_file",
        resource_id: file.public_id,
        action: :read,
        granted_by_id: user_a.id,
        tekoa_id: user_a.tekoa_id
      })
      |> Repo.insert()

  O anti-spoofing está na origem do attrs, não na lista de cast: um atacante
  não pode falsificar `granted_by_id` nem `tekoa_id` porque nenhum parâmetro
  externo chega a este changeset.

  ## Segurança

  - **Row-Level Security (RLS)** habilitado - queries filtradas por `app.current_tekoa_id`
  - **Anti-spoofing** - attrs construído pelo serviço com valores de confiança, nunca parâmetros externos
  - **Rastreabilidade** - granted_by_id é obrigatório: toda concessão registra quem concedeu
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Taina.Maraca

  @actions ~w(read write delete)a

  @type t :: %__MODULE__{
          id: integer() | nil,
          resource_id: String.t(),
          resource_type: String.t(),
          action: :read | :write | :delete,
          ava_id: integer(),
          ava: Maraca.Ava.t() | NotLoaded.t() | nil,
          tekoa_id: integer(),
          tekoa: Maraca.Tekoa.t() | NotLoaded.t() | nil,
          granted_by_id: integer() | nil,
          granted_by: Maraca.Ava.t() | NotLoaded.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  @schema_prefix "maraca"
  schema "permissions" do
    field :resource_id, :string
    field :resource_type, :string
    field :action, Ecto.Enum, values: @actions

    belongs_to :ava, Maraca.Ava
    belongs_to :tekoa, Maraca.Tekoa
    belongs_to :granted_by, Maraca.Ava

    timestamps()
  end

  @doc """
  Constrói o changeset de concessão de uma Permission.

  Único construtor de Permission: recebe os seis campos da concessão, todos
  obrigatórios, de modo que a trilha de auditoria nunca nasce pela metade.

  ## Campos obrigatórios

    * `ava_id` - Ava que receberá a permissão
    * `resource_type` - Tipo do recurso (ex: "ybira_file", "guara_chat")
    * `resource_id` - ID público do recurso
    * `action` - Ação permitida (:read, :write, :delete)
    * `granted_by_id` - Quem está concedendo (trilha de auditoria)
    * `tekoa_id` - Comunidade da concessão (isolamento RLS)

  O attrs é construído pelo serviço a partir do scope autenticado, nunca de
  parâmetros externos: é a origem dos valores, e não a lista de cast, que
  previne spoofing de `granted_by_id` e `tekoa_id`.

  ## Validações

    * Todas as ações devem estar na lista permitida: #{inspect(@actions)}
    * Combinação (ava_id, resource_type, resource_id, action) deve ser única
    * Retorna erro amigável se permissão duplicada for tentada

  ## Uso correto

      # No serviço Maraca:
      %Permission{}
      |> Permission.grant_changeset(%{
        ava_id: recipient.id,
        resource_type: "ybira_file",
        resource_id: file.public_id,
        action: :read,
        granted_by_id: granter.id,
        tekoa_id: granter.tekoa_id
      })
      |> Repo.insert()

  ## Exemplos

      iex> grant_changeset(%Permission{}, %{
      ...>   ava_id: recipient.id,
      ...>   resource_type: "ybira_file",
      ...>   resource_id: file.public_id,
      ...>   action: :read,
      ...>   granted_by_id: granter.id,
      ...>   tekoa_id: granter.tekoa_id
      ...> })
      %Ecto.Changeset{valid?: true}

      iex> grant_changeset(%Permission{}, %{action: :invalid})
      %Ecto.Changeset{valid?: false}
  """
  def grant_changeset(%__MODULE__{} = permission, %{} = attrs) do
    permission
    |> cast(attrs, [:resource_id, :resource_type, :action, :ava_id, :granted_by_id, :tekoa_id])
    |> validate_required([:resource_id, :resource_type, :action, :ava_id, :granted_by_id, :tekoa_id])
    |> unique_constraint(:action,
      name: "permissions_unique_grant",
      message: "já existe permissão para esta combinação de ava, recurso e ação"
    )
  end
end
