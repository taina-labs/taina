import Config

# The release config provider reads TAINA_CONFIG and installs the typed runtime
# settings. There are no per-setting environment overrides.
if System.get_env("PHX_SERVER") do
  config :taina, TainaWeb.Endpoint, server: true
end
