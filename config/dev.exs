import Config

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Configure your database. Honors the standard libpq env vars (PGHOST/PGUSER/…)
# so CI — and the `taina.backup.verify` round-trip — can point at a service DB
# without code changes; falls back to local defaults otherwise.
config :taina, Taina.Repo,
  username: System.get_env("PGUSER") || "postgres",
  password: System.get_env("PGPASSWORD") || "postgres",
  hostname: System.get_env("PGHOST") || "localhost",
  port: String.to_integer(System.get_env("PGPORT") || "5432"),
  database: System.get_env("PGDATABASE") || "taina_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :taina, TainaWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "318cH01aO0gWN9FThKaSqgINCNwdQL1PkE5zPLns0FQDdgKzFDfBj+VoM8OtCme/",
  watchers: []

# Local file storage for Ybira uploads
config :taina, :storage_root, Path.expand("../priv/storage", __DIR__)

# Enable dev routes for dashboard and mailbox
config :taina, dev_routes: true
