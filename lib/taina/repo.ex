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

  @tekoa_context_key :taina_current_tekoa_id

  # Tabelas de infraestrutura (schema `public`, sem RLS) que rodam fora de
  # qualquer Tekoa por natureza, hoje, a fila do Oban. O guard isenta SÓ estas:
  # qualquer outra tabela é tratada como dado de Tekoa e exige contexto. Assim,
  # schemas novos de fases futuras ficam protegidos por padrão, e esquecer de
  # isentar uma nova tabela de infra causa um erro barulhento, nunca um
  # vazamento silencioso.
  @infra_table_prefixes ~w(oban_)

  @doc """
  Executa uma função dentro do contexto de uma Tekoa específica.

  Esta função é fundamental para o isolamento de comunidades no Tainá. Ela:
  1. Marca o processo atual com o contexto da Tekoa (verificado por `prepare_query/3`)
  2. Inicia uma transação
  3. Define a variável PostgreSQL `app.current_tekoa_id`
  4. Executa o callback fornecido
  5. Políticas RLS usam essa variável para filtrar dados automaticamente

  O callback deve retornar `{:ok, valor}` ou `{:error, motivo}` (contrato de
  `Repo.transact/2`): `{:error, _}` desfaz a transação.

  ## Isolamento por RLS

  Todas as tabelas principais do Tainá possuem políticas RLS que verificam:
  ```sql
  USING (tekoa_id = current_setting('app.current_tekoa_id', true)::VARCHAR)
  ```

  Isso garante que mesmo se o código da aplicação esquecer de filtrar por `tekoa_id`,
  o banco de dados impedirá vazamento de dados entre comunidades.

  ## Parâmetros

    * `tekoa_public_id` - **`public_id`** da Tekoa (as políticas RLS comparam
      `maraca.tekoas.public_id` com `app.current_tekoa_id`)
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

  **IMPORTANTE**: Queries executadas fora de `with_tekoa/2` levantam exceção
  (via `prepare_query/3`), a menos que recebam a opção `skip_tekoa_id: true`,
  reservada para operações de sistema (bootstrap de autenticação, lookups
  pré-contexto, jobs administrativos).
  """
  def with_tekoa(tekoa_public_id, cb) do
    public_id = to_string(tekoa_public_id)
    previous = Process.put(@tekoa_context_key, public_id)

    try do
      transact(fn ->
        SQL.query!(
          __MODULE__,
          "SELECT set_config('app.current_tekoa_id', $1, true)",
          [public_id]
        )

        cb.()
      end)
    after
      if is_nil(previous) do
        Process.delete(@tekoa_context_key)
      else
        Process.put(@tekoa_context_key, previous)
      end
    end
  end

  @doc """
  Executa uma função como operação de sistema, cruzando as políticas RLS.

  A válvula que espelha, no banco, o que `skip_tekoa_id: true` espelha na
  aplicação. Em produção a aplicação conecta como um papel sem superpoderes
  (`NOSUPERUSER NOBYPASSRLS`), então **toda** query cruza as políticas RLS,
  inclusive as de sistema. `skip_tekoa_id: true` só isenta a query da exceção
  de contexto em `prepare_query/3`; no banco, sem contexto definido, as
  policies esconderiam as linhas. `with_system/1` abre uma transação e define
  `app.bypass_rls = 'on'`, o que faz a política de cada tabela passar a valer
  (o `OR current_setting('app.bypass_rls', true) = 'on'` nas políticas).

  1. Inicia uma transação
  2. Define a variável PostgreSQL `app.bypass_rls` como `'on'`, **só para a
     transação** (o terceiro argumento de `set_config/3`)
  3. Executa o callback fornecido
  4. Ao fim, a válvula morre com a transação: nada vaza para a conexão

  O callback deve retornar `{:ok, valor}` ou `{:error, motivo}` (contrato de
  `Repo.transact/1`): `{:error, _}` desfaz a transação.

  ## Quando usar

  Somente nas mesmas operações que hoje declaram `skip_tekoa_id: true`:
  bootstrap de autenticação, resolução de sessão pré-contexto, jobs e tarefas
  administrativas que cruzam Tekoas. Nenhuma trilha movida por pedido de
  usuário deve passar por aqui: o caminho normal continua sendo `with_tekoa/2`
  com o contexto da comunidade. Se um dia duas válvulas disputarem o mesmo
  site, o problema é de desenho, não de uma delas faltar.

  ## Segurança

  A válvula é do nível da aplicação, não do banco: quem se conecta como
  superuser (dev e teste, papel `postgres`) ignora RLS por definição e ela é
  no-op. Ela existe para o papel de produção (`taina_app`), que não tem como
  escalar além do que `app.bypass_rls` permitir, e ele só é `'on'` dentro da
  transação que o próprio sistema abriu, nunca num request de morador.

  Nunca chame `with_system/1` dentro de `with_tekoa/2`: o Ecto absorve a
  transação aninhada em vez de criar um savepoint, então a válvula vazaria
  para o resto da transação externa (as queries de morador seguintes cruzariam
  as políticas). Chamar assim levanta erro.

  ## Exemplos

      # Bootstrap: saber se já existe comunidade, cruzando o RLS
      iex> Repo.with_system(fn -> {:ok, Repo.exists?(Tekoa, skip_tekoa_id: true)} end)
      {:ok, true}

      # Job de sistema que cruza todas as Tekoas
      iex> Repo.with_system(fn -> {:ok, Repo.all(Taina.Ybira.File, skip_tekoa_id: true)} end)
      {:ok, [%File{}, %File{}]}
  """
  def with_system(cb) do
    if in_tekoa_context?() do
      raise """
      `with_system/1` dentro de `with_tekoa/2`: o Ecto absorve a transação \
      aninhada em vez de criar um savepoint, então a válvula de sistema \
      vazaria para o resto da transação externa e as queries de morador \
      seguintes cruzariam as políticas RLS. Operações de sistema devem rodar \
      fora de `with_tekoa/2`.
      """
    end

    transact(fn ->
      SQL.query!(__MODULE__, "SELECT set_config('app.bypass_rls', 'on', true)", [])
      cb.()
    end)
  end

  @doc """
  Rede de segurança do isolamento multi-tenant.

  Toda query (`all`, `one`, `get*`, `update_all`, `delete_all`, preloads)
  precisa rodar dentro de `with_tekoa/2` ou declarar explicitamente
  `skip_tekoa_id: true`. Sem isso, levanta exceção em vez de retornar dados
  vazios silenciosamente, esquecer o contexto vira erro de desenvolvimento,
  não vazamento ou comportamento fantasma em produção.

  A única isenção automática são as tabelas de infraestrutura listadas em
  `@infra_table_prefixes` (a fila do Oban): elas não guardam dado de Tekoa.
  Tudo o mais raiseia por padrão, o lado seguro.

  Inserts/updates/deletes de structs não passam por este callback; para eles a
  proteção é o RLS no banco (`WITH CHECK` das policies + `FORCE ROW LEVEL
  SECURITY`).
  """
  @impl true
  def prepare_query(_operation, query, opts) do
    cond do
      opts[:skip_tekoa_id] || opts[:schema_migration] ->
        {query, opts}

      in_tekoa_context?() ->
        {query, opts}

      infra_query?(query) ->
        {query, opts}

      true ->
        raise """
        query executada fora do contexto de Tekoa: #{inspect(query)}

        Envolva a operação em `Taina.Repo.with_tekoa/2` ou, se esta é uma \
        operação de sistema (bootstrap de auth, migração, job administrativo), \
        passe a opção `skip_tekoa_id: true` explicitamente.
        """
    end
  end

  # Espelho exato da chave que `with_tekoa/2` põe no dicionário do processo:
  # se está aqui (não nil), estamos dentro de um contexto de Tekoa, e é o que
  # `with_system/1` usa para se recusar aninhado.
  defp in_tekoa_context?, do: is_binary(Process.get(@tekoa_context_key))

  # Isenta apenas tabelas de infraestrutura, identificadas pelo nome (ex.:
  # `oban_jobs`, `oban_peers`). Lê só o nome da tabela na cláusula `from`, sem
  # introspecção de schema, e, no que não reconhecer, raiseia (lado seguro).
  defp infra_query?(%Ecto.Query{from: %{source: {table, _schema}}}) when is_binary(table) do
    String.starts_with?(table, @infra_table_prefixes)
  end

  defp infra_query?(_query), do: false

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
  def fetch(schema, id, opts \\ []) do
    if e = get(schema, id, opts) do
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
