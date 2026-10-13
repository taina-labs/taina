import Config

alias Ecto.Adapters.SQL.Sandbox

# SQLite por partição de teste: um arquivo temporario por MIX_TEST_PARTITION,
# recriado do zero pelo `mix test` (ecto.create + ecto.migrate).
test_db =
  Path.join(
    System.tmp_dir!(),
    "taina_test#{System.get_env("MIX_TEST_PARTITION")}.db"
  )

# Fast password hashing in tests
config :bcrypt_elixir, log_rounds: 4

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Jobs rodam síncronos (inline) no processo de teste, dentro do sandbox Ecto,
# sem filas nem cron de verdade.
config :taina, Oban, testing: :inline

config :taina, Taina.Repo,
  database: test_db,
  pool: Sandbox,
  pool_size: System.schedulers_online() * 2,
  journal_mode: :wal,
  busy_timeout: 5_000,
  default_transaction_mode: :immediate

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :taina, TainaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "bf9kxtNUgDlvtHPEms1ROPbUnGMIhE2kotcm4HbyzxHX9uWULOiSiBQ97QAGwAGm",
  server: false

config :taina,
       :storage_root,
       Path.join(System.tmp_dir!(), "taina_test_storage#{System.get_env("MIX_TEST_PARTITION")}")
