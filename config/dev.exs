import Config

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Configure your database
config :taina, Taina.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "taina_dev",
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

# Enable dev routes for dashboard and mailbox
config :taina, dev_routes: true
