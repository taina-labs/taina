# General application configuration
import Config

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, JSON

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

config :taina,
  ecto_repos: [Taina.Repo],
  generators: [timestamp_type: :utc_datetime]

import_config "#{config_env()}.exs"
