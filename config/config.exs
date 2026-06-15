# General application configuration
import Config

# esbuild empacota JS e CSS (imports nativos); sem Tailwind, CSS puro com
# tokens do Penpot (ver assets/css/tokens.css).
config :esbuild,
  version: "0.25.4",
  taina: [
    args: ~w(js/app.js css/app.css --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :path, :file_id, :reason, :errors]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, JSON

# Background jobs. PurgeTrash apaga de vez os arquivos na lixeira há mais de
# 30 dias, todo dia às 03:00 (ver Taina.Ybira.Workers.PurgeTrash).
config :taina, Oban,
  engine: Oban.Engines.Basic,
  repo: Taina.Repo,
  queues: [default: 10],
  plugins: [
    {Oban.Plugins.Cron, crontab: [{"0 3 * * *", Taina.Ybira.Workers.PurgeTrash}]}
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

# UI pt-BR primeiro (RFC 002); outros idiomas entram como .po quando houver demanda.
config :taina, TainaWeb.Gettext, default_locale: "pt_BR"

config :taina,
  ecto_repos: [Taina.Repo],
  generators: [timestamp_type: :utc_datetime]

import_config "#{config_env()}.exs"
