# General application configuration
import Config

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :path, :file_id, :reason, :errors]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, JSON

# Background jobs.
#   - PurgeTrash apaga de vez os arquivos na lixeira há mais de 30 dias (03:00).
#   - Backup faz pg_dump + arquivo do storage (04:00). É no-op até habilitar
#     `config :taina, :backup, enabled: true` (ver Taina.Nhaman.Backup).
config :taina, Oban,
  engine: Oban.Engines.Basic,
  repo: Taina.Repo,
  queues: [default: 10],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", Taina.Ybira.Workers.PurgeTrash},
       {"0 4 * * *", Taina.Nhaman.Workers.Backup}
     ]}
  ]

# Configures the endpoint
config :taina, TainaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: TainaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Taina.PubSub,
  live_view: [signing_salt: "rV2D3nM4"]

# Backup desabilitado por padrão (a tarefa agendada vira no-op). O instalador /
# admin liga via runtime (`BACKUP_ENABLED=true`, `BACKUP_DIR=...`).
config :taina, :backup, enabled: false

config :taina,
  ecto_repos: [Taina.Repo],
  generators: [timestamp_type: :utc_datetime]

import_config "#{config_env()}.exs"
