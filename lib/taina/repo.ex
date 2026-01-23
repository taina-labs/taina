defmodule Taina.Repo do
  @moduledoc """
  Repositório principal do Tainá com suporte a Row-Level Security (RLS).

  Este módulo estende o `Ecto.Repo` padrão com funcionalidades específicas
  do Tainá, principalmente o isolamento de comunidades através de RLS.
  """

  use Ecto.Repo,
    otp_app: :taina,
    adapter: Ecto.Adapters.Postgres

  alias Ecto.Adapters.SQL

  @doc """
  Executa uma função dentro do contexto de uma Tekoa específica.

  Esta função é fundamental para o isolamento de comunidades no Tainá. Ela:
  1. Inicia uma transação
  2. Define a variável PostgreSQL `app.current_tekoa_id`
  3. Executa o callback fornecido
  4. Políticas RLS usam essa variável para filtrar dados automaticamente

  ## Isolamento por RLS

  Todas as tabelas principais do Tainá possuem políticas RLS que verificam:
  ```sql
  USING (tekoa_id = current_setting('app.current_tekoa_id', true)::VARCHAR)
  ```

  Isso garante que mesmo se o código da aplicação esquecer de filtrar por `tekoa_id`,
  o banco de dados impedirá vazamento de dados entre comunidades.

  ## Parâmetros

    * `tekoa_id` - ID da Tekoa (pode ser string ou qualquer tipo que implemente `String.Chars`)
    * `cb` - Função callback que será executada dentro do contexto da Tekoa

  ## Exemplos

      # Listar arquivos de uma comunidade específica
      iex> Repo.with_tekoa(tekoa.id, fn ->
      ...>   Repo.all(Ybira.File)
      ...> end)
      {:ok, [%File{}, %File{}]}  # Apenas arquivos da tekoa especificada

      # Mesmo sem filtro explícito, RLS garante isolamento
      iex> Repo.with_tekoa("tekoa_123", fn ->
      ...>   # Esta query não filtra por tekoa_id explicitamente
      ...>   Repo.all(Maraca.Ava)
      ...> end)
      {:ok, [%Ava{}]}  # RLS filtra automaticamente

  ## Segurança

  Esta função é crítica para a segurança do sistema. Use-a sempre que:
  - Executar queries em tabelas com RLS habilitado
  - Processar requisições de usuários (cada usuário pertence a uma Tekoa)
  - Realizar operações em background jobs que manipulam dados de uma Tekoa

  **IMPORTANTE**: Não executar queries sem contexto de Tekoa pode resultar em
  acesso negado ou dados vazios, pois as políticas RLS não terão como filtrar.
  """
  def with_tekoa(tekoa_id, cb) do
    transact(fn ->
      SQL.query!(
        __MODULE__,
        "SELECT set_config('app.current_tekoa_id', $1, true)",
        [to_string(tekoa_id)]
      )

      cb.()
    end)
  end

  @doc """
  Busca uma entidade por ID e retorna `{:ok, entity}` ou `{:error, :not_found}`.

  Esta é uma versão conveniente de `Repo.get/2` que retorna uma tupla tagged,
  facilitando o uso com `with` e pattern matching no Elixir.

  ## Parâmetros

    * `schema` - Módulo do schema Ecto (ex: `Taina.Maraca.Ava`)
    * `id` - ID da entidade (inteiro ou string, dependendo do schema)

  ## Retorno

    * `{:ok, entity}` - Se a entidade foi encontrada
    * `{:error, :not_found}` - Se não existe entidade com esse ID

  ## Exemplos

      # Sucesso ao encontrar
      iex> Repo.fetch(Ava, 1)
      {:ok, %Ava{id: 1, username: "maria"}}

      # Falha ao não encontrar
      iex> Repo.fetch(Ava, 999999)
      {:error, :not_found}

      # Uso com `with` para encadear operações
      iex> with {:ok, ava} <- Repo.fetch(Ava, ava_id),
      ...>      {:ok, file} <- Repo.fetch(File, file_id),
      ...>      :ok <- Auth.authorize(ava, :read, file) do
      ...>   {:ok, file}
      ...> end

  ## Notas

  Esta função respeita o contexto RLS se estiver dentro de `with_tekoa/2`.
  Se executada fora do contexto de uma Tekoa, pode retornar `:not_found`
  mesmo que a entidade exista (por causa das políticas RLS).
  """
  def fetch(schema, id) do
    if e = get(schema, id) do
      {:ok, e}
    else
      {:error, :not_found}
    end
  end
end

defmodule Taina.Repo.PublicId do
  @moduledoc """
  Tipo customizado Ecto para IDs públicos seguros.

  Este tipo gera automaticamente identificadores únicos usando Nanoid (12 caracteres)
  que são seguros para expor em APIs públicas, URLs e interfaces de usuário.

  ## Por que não usar IDs sequenciais?

  IDs sequenciais do banco de dados (1, 2, 3...) têm problemas:
  - **Segurança**: Expõem informações sobre volume de dados
  - **Enumeração**: Facilitam ataques de força bruta (tentar /users/1, /users/2, etc.)
  - **Previsibilidade**: Fácil adivinhar IDs de outros recursos

  ## Vantagens do PublicId

  - **Não sequencial**: Impossível enumerar ou prever
  - **Compacto**: 12 caracteres (vs 36 de UUID)
  - **URL-friendly**: Apenas caracteres seguros (A-Za-z0-9_-)
  - **Único**: Colisão estatisticamente impossível
  - **Rápido**: Geração mais eficiente que UUID

  ## Uso em schemas

      defmodule Taina.Maraca.Ava do
        use Ecto.Schema
        alias Taina.Repo.PublicId

        schema "avas" do
          field :public_id, PublicId, autogenerate: true
          # ...
        end
      end

  ## Exemplos de IDs gerados

      iex> Taina.Repo.PublicId.autogenerate()
      "V1StGXR8_Z5j"

      iex> Taina.Repo.PublicId.autogenerate()
      "A9fK2mN7pQ3x"

  ## Formato

  - **Tamanho**: 12 caracteres
  - **Alfabeto**: `A-Za-z0-9_-` (URL-safe)
  - **Biblioteca**: Nanoid
  - **Tipo no banco**: VARCHAR/STRING

  ## Segurança

  Use sempre `public_id` para:
  - URLs de API (`/api/files/:public_id`)
  - Resposta JSON (`{"id": "V1StGXR8_Z5j"}`)
  - Links compartilháveis
  - Referências externas

  **NUNCA exponha** `id` (chave primária do banco) publicamente.
  """

  use Ecto.Type

  @impl true
  def type, do: :string

  @impl true
  def cast(id) when is_binary(id), do: {:ok, id}
  def cast(_), do: :error

  @impl true
  def load(value), do: {:ok, value}

  @impl true
  def dump(value) when is_binary(value), do: {:ok, value}
  def dump(_), do: :error

  @impl true
  def autogenerate, do: Nanoid.generate(12)
end
