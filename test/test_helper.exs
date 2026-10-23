alias Ecto.Adapters.SQL.Sandbox

# O repo dos testes do kernel (Ypy.TestRepo) mora num arquivo SQLite efemero:
# o `:memory:` do ecto_sqlite3 nao atravessa conexoes (o exqlite nao abre com
# SQLITE_OPEN_URI), e o migrador precisa de duas conexoes (trava mais
# migracao). Entao o boot cria e migra com o pool comum, e troca para o pool do
# sandbox sobre o mesmo arquivo. As migracoes sao as do kernel
# (`priv/ypy/migrations`), nao as do produto.
db =
  Path.join(
    System.tmp_dir!(),
    "taina-ypy-test-#{System.unique_integer([:positive])}.sqlite"
  )

{:ok, _} = Ypy.TestRepo.start_link(database: db, pool_size: 2)

Ecto.Migrator.run(Ypy.TestRepo, Path.join(File.cwd!(), "priv/ypy/migrations"), :up, all: true)

:ok = Ypy.TestRepo.stop()

{:ok, _} = Ypy.TestRepo.start_link(database: db, pool_size: 2, pool: Sandbox)

Sandbox.mode(Ypy.TestRepo, :manual)

# O `:map` do ecto_sqlite3 serializa por uma lib configuravel; o kernel usa a
# que vem com o proprio Elixir.
Application.put_env(:ecto_sqlite3, :json_library, JSON)

# Apagar sem fechar: o WAL guarda o que o checkpoint ainda nao despejou. O
# sandbox volta a automatico porque a suite acabou e ninguem tem a conexao.
ExUnit.after_suite(fn _results ->
  Sandbox.mode(Ypy.TestRepo, :auto)
  {:ok, _} = Ypy.TestRepo.query("PRAGMA wal_checkpoint(TRUNCATE)")
  :ok = Ypy.TestRepo.stop()
  File.rm(db)
end)

# `max_cases: 1`: o sandbox do Ecto nao e async no SQLite (só um write
# transaction por vez), entao a suíte roda serializada. `capture_log`: cada
# teste captura o Logger e só imprime o que capturou se falhar -- `mix test`
# fica limpo quando tudo passa, e o aviso que explica a falha aparece colado
# no teste que quebrou. Sinais do app (workers, tarefas) continuam capturados
# aqui; o que não é Logger (IO cru) é capturado no teste que o produz, com
# `ExUnit.CaptureIO`.
ExUnit.start(capture_log: true, max_cases: 1)
Sandbox.mode(Taina.Repo, :manual)
