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

  ## Exemplos de uso

      # Usuário A compartilha arquivo com Usuário B (leitura)
      iex> changeset(%Permission{}, %{
      ...>   ava_id: user_b.id,
      ...>   resource_type: "ybira_file",
      ...>   resource_id: file.public_id,
      ...>   action: :read,
      ...>   granted_by_id: user_a.id,
      ...>   tekoa_id: tekoa.id
      ...> })
      %Ecto.Changeset{valid?: true}

  ## Segurança

  Esta tabela possui Row-Level Security (RLS) habilitado. Todas as queries são automaticamente
  filtradas pela Tekoa atual através do contexto `app.current_tekoa_id`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Taina.Maraca

  @actions ~w(read write delete share)a

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

  ## Campos obrigatórios

    * `ava_id` - Ava que receberá a permissão
    * `resource_type` - Tipo do recurso (ex: "ybira_file", "guara_chat")
    * `resource_id` - ID público do recurso
    * `action` - Ação permitida (:read, :write, :delete, :share)
    * `granted_by_id` - Ava que está concedendo a permissão
    * `tekoa_id` - Comunidade onde a permissão é válida

  ## Validações

    * Todas as ações devem estar na lista permitida: #{inspect(@actions)}
    * Combinação (ava_id, resource_type, resource_id, action) deve ser única

  ## Exemplos

      iex> changeset(%Permission{}, %{
      ...>   ava_id: "ava_123",
      ...>   resource_type: "ybira_file",
      ...>   resource_id: "file_456",
      ...>   action: :read,
      ...>   granted_by_id: "ava_789",
      ...>   tekoa_id: "tekoa_111"
      ...> })
      %Ecto.Changeset{valid?: true}

      iex> changeset(%Permission{}, %{action: :invalid})
      %Ecto.Changeset{valid?: false}
  """
  def changeset(%__MODULE__{} = permission, %{} = attrs) do
    permission
    |> cast(attrs, [:resource_id, :resource_type, :action, :ava_id, :tekoa_id, :granted_by_id])
    |> validate_required([:resource_id, :resource_type, :action, :ava_id, :tekoa_id, :granted_by_id])
  end
end
