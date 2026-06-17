import Config

# Do not print debug messages in production
config :logger, level: :info

# Assets fingerprinted por `mix assets.deploy` (esbuild --minify + phx.digest).
config :taina, TainaWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"
