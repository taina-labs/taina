import Config

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/taina start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :taina, TainaWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  # Interface que o listener HTTP usa. Padrão 0.0.0.0: no container a porta é
  # publicada em loopback pelo Docker. O módulo NixOS aponta para 127.0.0.1,
  # já que o proxy reverso roda na mesma caixa.
  bind_ip =
    case :inet.parse_address(String.to_charlist(System.get_env("BIND_IP") || "0.0.0.0")) do
      {:ok, ip} -> ip
      {:error, _} -> raise "BIND_IP is not a valid IP address"
    end

  # Esquema e porta das URLs que o app monta (convites, links). Padrão https na
  # 443, que é o caso atrás de um proxy com TLS. Numa caixa sem proxy, aponte
  # para http na porta do próprio listener.
  url_scheme = System.get_env("PHX_URL_SCHEME") || "https"
  url_port = String.to_integer(System.get_env("PHX_URL_PORT") || "443")

  # Ajuste de fila do pool (RFC_ARQUITETURA): uma query espera no máximo 50ms
  # na fila, checando a cada 1s se a fila encheu. No teto de 20 conexões do
  # Postgres da caixa, é o que evita request acumulando sem ninguém notar.
  config :taina, Taina.Repo,
    queue_target: 50,
    queue_interval: 1000

  config :taina, Taina.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # A caixa é alcançada por nomes arbitrários (endereço de LAN, MagicDNS do
  # Tailscale, domínio próprio): qualquer allowlist de origin quebra um desses
  # caminhos. Desligado de propósito: a sessão é SameSite=Lax e os params de
  # LiveView são assinados, o que cobre o vetor que check_origin mitiga.
  config :taina, TainaWeb.Endpoint, check_origin: false

  config :taina, TainaWeb.Endpoint,
    url: [host: host, port: url_port, scheme: url_scheme],
    http: [
      ip: bind_ip,
      port: port
    ],
    secret_key_base: secret_key_base

  # Scheduled backups (Nhaman). Off unless BACKUP_ENABLED is truthy; BACKUP_DIR
  # should point at a mounted USB disk or an rclone-synced path. BACKUP_DATABASE_URL
  # is the superuser connection (postgresql:// scheme) pg_dump/pg_restore use:
  # in production the app's own DATABASE_URL is the restricted taina_app role,
  # which cannot read other roles' objects during a restore. Unset (dev/CI,
  # single postgres role), the backup falls back to the Repo URL.
  config :taina, :backup,
    enabled: System.get_env("BACKUP_ENABLED") in ~w(true 1),
    dir: System.get_env("BACKUP_DIR") || "/app/backups",
    database_url: System.get_env("BACKUP_DATABASE_URL")

  config :taina, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # File storage root for Ybira. The Dockerfile creates /app/storage owned
  # by the runtime user; docker-compose mounts the storage_data volume there.
  config :taina, :storage_root, System.get_env("STORAGE_ROOT") || "/app/storage"

  # Opt-in update check (Nhaman): off unless the operator asks for it. When on,
  # the box makes one plain GET to the public releases URL, nothing else
  # (see Taina.Nhaman.Update for the sovereignty trade-off).
  config :taina, :update_check, enabled: System.get_env("TAINA_UPDATE_CHECK") in ~w(true 1)
end
