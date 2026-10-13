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
  # SQLite: o banco e um arquivo na caixa, nao um servico remoto. DATABASE_URL
  # (`sqlite:///caminho`) e opcional; sem ele, cai no caminho padrao do
  # container (ver o bloco do Repo abaixo).

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

  # SQLite: o "database" e um caminho de arquivo na caixa. Aceita o padrao do
  # container (DATABASE_PATH) e um `sqlite:///abs/path` no DATABASE_URL; uma
  # URL de Postgres em DATABASE_URL e recusada em vez de quebrar no boot.
  database_path =
    case System.get_env("DATABASE_URL") do
      nil -> System.get_env("DATABASE_PATH") || "/app/data/taina.db"
      "sqlite://" <> rest -> String.trim_leading(rest, "/")
      other -> raise "DATABASE_URL incompativel com SQLite (esperado sqlite://): #{other}"
    end

  config :taina, Taina.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # Escritor pega o lock no BEGIN: o busy_timeout nao cobre a leitura que
    # vira escrita depois de outro escritor commitou (SQLITE_BUSY_SNAPSHOT) --
    # o caso upload (box) x rendition (Oban).
    default_transaction_mode: :immediate

  # Ajuste de fila do pool (RFC_ARQUITETURA): uma query espera no maximo 50ms
  # na fila, checando a cada 1s se a fila encheu.
  config :taina, Taina.Repo,
    queue_target: 50,
    queue_interval: 1000

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
  # should point at a mounted USB disk or an rclone-synced path. The backup is a
  # SQLite snapshot (VACUUM INTO) of the same file the app uses, so there is no
  # second connection to configure.
  config :taina, :backup,
    enabled: System.get_env("BACKUP_ENABLED") in ~w(true 1),
    dir: System.get_env("BACKUP_DIR") || "/app/backups"

  config :taina, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # File storage root for Ybira. The Dockerfile creates /app/storage (and the
  # /app/data holding the SQLite file) owned by the runtime user; docker-compose
  # mounts the storage_data and data_data volumes there.
  config :taina, :storage_root, System.get_env("STORAGE_ROOT") || "/app/storage"

  # Opt-in update check (Nhaman): off unless the operator asks for it. When on,
  # the box makes one plain GET to the public releases URL, nothing else
  # (see Taina.Nhaman.Update for the sovereignty trade-off).
  config :taina, :update_check, enabled: System.get_env("TAINA_UPDATE_CHECK") in ~w(true 1)
end
