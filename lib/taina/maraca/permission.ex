defmodule Taina.Maraca.Permission do
  @moduledoc """
  Representa uma permissão explícita concedida a um Ava para acessar um recurso específico.

  No Tainá, seguimos o princípio de que **os usuários são donos de seus dados**. Isso significa
  que permissões devem ser explícitas - nenhum acesso é concedido automaticamente, nem mesmo
  para administradores. Cada Permission registra quem pode fazer o quê com qual recurso.

  ## Filosofia

  Diferente de sistemas tradicionais onde administradores têm acesso irrestrito, no Tainá:
  - Proprietários de recursos controlam totalmente o acesso
  - Administradores devem solicitar permissão via AccessRequest
  - Todas as permissões são rastreáveis e revogáveis

  ## Campos principais

    * `ava_id` - ID do Ava que recebe a permissão
    * `resource_type` - Tipo do recurso (ex: "ybira_file", "ybira_folder", "guara_chat")
    * `resource_id` - ID público do recurso específico
    * `action` - Ação permitida: :read, :write, :delete, ou :share
    * `granted_by_id` - ID do Ava que concedeu a permissão (rastreabilidade)
    * `tekoa_id` - Comunidade à qual a permissão pertence (isolamento RLS)

  ## Ordem de resolução de permissões

  1. **Isolamento de comunidade** - RLS garante que apenas recursos da mesma Tekoa sejam visíveis
  2. **Propriedade do recurso** - Donos têm acesso total automaticamente
  3. **Permissões explícitas** - Verificadas nesta tabela
  4. **Negação padrão** - Se nada acima se aplicar, acesso negado

  ## Uso correto (anti-spoofing)

  O changeset **NÃO** aceita `granted_by_id` nem `tekoa_id` via parâmetros.
  Esses campos devem ser definidos explicitamente pelo serviço:

      # Usuário A compartilha arquivo com Usuário B (leitura)
      %Permission{}
      |> Permission.changeset(%{
        ava_id: user_b.id,
        resource_type: "ybira_file",
        resource_id: file.public_id,
        action: :read
      })
      |> Ecto.Changeset.put_change(:granted_by_id, user_a.id)
      |> Ecto.Changeset.put_change(:tekoa_id, user_a.tekoa_id)
      |> Repo.insert()

  Isso previne spoofing: um atacante não pode falsificar `granted_by_id` ou
  `tekoa_id` via parâmetros externos. Apenas o código do serviço define esses campos.

  ## Segurança

  - **Row-Level Security (RLS)** habilitado - queries filtradas por `app.current_tekoa_id`
  - **Anti-spoofing** - campos de contexto não aceitos via parâmetros externos
  - **Rastreabilidade** - `granted_by_id` sempre reflete quem realmente concedeu
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Taina.Maraca

  @actions ~w(read write delete share)a

  @type t :: %__MODULE__{
          id: integer() | nil,
          resource_id: String.t(),
          resource_type: String.t(),
          action: :read | :write | :delete | :share,
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
  Valida uma Permission com as informações fornecidas.

  ## Campos aceitos via parâmetros

    * `ava_id` - Ava que receberá a permissão
    * `resource_type` - Tipo do recurso (ex: "ybira_file", "guara_chat")
    * `resource_id` - ID público do recurso
    * `action` - Ação permitida (:read, :write, :delete, :share)

  ## Campos de contexto (NÃO vêm de parâmetros)

  Os seguintes campos devem ser definidos explicitamente pelo serviço antes de persistir:

    * `granted_by_id` - Definido pelo serviço (quem está concedendo)
    * `tekoa_id` - Definido pelo contexto RLS atual

  ## Validações

    * Todas as ações devem estar na lista permitida: #{inspect(@actions)}
    * Combinação (ava_id, resource_type, resource_id, action) deve ser única
    * Retorna erro amigável se permissão duplicada for tentada

  ## Uso correto

      # No serviço Maraca.Public:
      %Permission{}
      |> Permission.changeset(%{
        ava_id: recipient.id,
        resource_type: "ybira_file",
        resource_id: file.public_id,
        action: :read
      })
      |> Ecto.Changeset.put_change(:granted_by_id, granter.id)
      |> Ecto.Changeset.put_change(:tekoa_id, granter.tekoa_id)
      |> Repo.insert()

  ## Segurança

  Este design previne spoofing de `granted_by_id` e `tekoa_id` via parâmetros externos.
  Apenas o código do serviço pode definir esses campos, garantindo rastreabilidade.

  ## Exemplos

      iex> changeset(%Permission{}, %{
      ...>   ava_id: recipient.id,
      ...>   resource_type: "ybira_file",
      ...>   resource_id: file.public_id,
      ...>   action: :read
      ...> })
      %Ecto.Changeset{valid?: true}

      iex> changeset(%Permission{}, %{action: :invalid})
      %Ecto.Changeset{valid?: false}

      # Tentativa de criar permissão duplicada
      iex> changeset(%Permission{}, %{
      ...>   ava_id: existing_permission.ava_id,
      ...>   resource_type: existing_permission.resource_type,
      ...>   resource_id: existing_permission.resource_id,
      ...>   action: existing_permission.action
      ...> })
      # Após Repo.insert/1, retorna erro:
      # {:error, %Ecto.Changeset{errors: [action: {"já existe permissão...", [constraint: :unique]}]}}
  """
  def changeset(%__MODULE__{} = permission, %{} = attrs) do
    permission
    |> cast(attrs, [:resource_id, :resource_type, :action, :ava_id, :granted_by_id, :tekoa_id])
    |> validate_required([:resource_id, :resource_type, :action, :ava_id, :granted_by_id, :tekoa_id])
    |> unique_constraint(:action,
      name: "permissions_unique_grant",
      message: "já existe permissão para esta combinação de ava, recurso e ação"
    )
  end
end
