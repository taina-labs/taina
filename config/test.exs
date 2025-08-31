import Config

alias Ecto.Adapters.SQL.Sandbox

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

if db_url = System.get_env("DATABASE_URL") do
  config :taina, Taina.Repo,
    url: db_url,
    pool: Sandbox,
    pool_size: System.schedulers_online() * 2
else
  config :taina, Taina.Repo,
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    database: "taina_test#{System.get_env("MIX_TEST_PARTITION")}",
    pool: Sandbox,
    pool_size: System.schedulers_online() * 2
end

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :taina, TainaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "bf9kxtNUgDlvtHPEms1ROPbUnGMIhE2kotcm4HbyzxHX9uWULOiSiBQ97QAGwAGm",
  server: false
