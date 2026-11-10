#!/bin/sh
set -eu

image=@IMAGE@
container=@CONTAINER@
service=@SERVICE@
data_dir=@DATA_DIR@
storage_dir=@STORAGE_DIR@
config_file=@CONFIG_FILE@
backup_dir=@BACKUP_DIR@
user_spec=@USER_SPEC@
newline=$(printf '\nx')
newline=${newline%x}

require_mount() {
  mountpoint -q "$1" || die 3 "required mount is not available: $1"
}

require_storage() {
@STORAGE_CHECKS@
}

die() {
  code=$1
  shift
  printf 'error: %s\n' "$*" >&2
  exit "$code"
}

usage() {
  cat <<'USAGE'
usage: taina <command> [arguments]

  backup                    write an archive under the backup directory
  restore ARCHIVE_NAME      restore cold from the backup directory
  <domain command>          run a command in a one-off container

Lifecycle belongs to systemd:
  sudo systemctl stop taina
  sudo systemctl start taina
  journalctl -u taina -f
USAGE
}

need_docker() {
  command -v docker >/dev/null 2>&1 || die 3 "docker is required for this deployment"
  docker info >/dev/null 2>&1 || die 3 "the Docker daemon is not running"
}

docker_run() {
  if [ -t 0 ] && [ -t 1 ]; then set -- -it "$@"; else set -- -i "$@"; fi
  docker run --rm "$@"
}

run_container() {
  need_docker
  require_storage
  docker_run --user "$user_spec" --workdir /data \
    --env TAINA_CONFIG=/data/taina.conf \
    --mount "type=bind,source=$data_dir,target=/data" \
    --mount "type=bind,source=$storage_dir,target=/app/storage" \
    --mount "type=bind,source=$backup_dir,target=/app/backups" \
    --mount "type=bind,source=$config_file,target=/data/taina.conf,readonly" \
    --entrypoint /app/bin/cli "$@"
}

assert_stopped() {
  need_docker
  state=$(systemctl show --property=ActiveState --value "$service") || die 3 "could not query $service state"
  [ "$state" = inactive ] || die 3 "$service is $state; stop it before restore"
  running=$(docker ps --quiet --filter "name=^/${container}$") || die 3 "could not query service container"
  [ -z "$running" ] || die 3 "the service container is running"
}

backup() {
  [ "$#" -eq 0 ] || { [ "$#" -eq 2 ] && [ "$1" = --out ] && [ "$2" = /app/backups ] || die 2 "backups are written only to $backup_dir"; }
  run_container "$image" backup --out /app/backups
}

restore() {
  [ "$#" -eq 1 ] || die 2 "usage: taina restore ARCHIVE_NAME"
  archive=$1
  case "$archive" in '' | . | .. | -* | */* | *"$newline"*) die 2 "ARCHIVE_NAME must be a filename inside $backup_dir" ;; esac
  [ -f "$backup_dir/$archive" ] || die 1 "backup archive not found: $backup_dir/$archive"
  assert_stopped
  run_container "$image" restore "/app/backups/$archive"
}

main() {
  [ "$#" -gt 0 ] || { usage; return 2; }
  command=$1; shift
  case "$command" in
    --help | -h | help) usage ;;
    backup) backup "$@" ;;
    restore) restore "$@" ;;
    *) run_container "$image" "$command" "$@" ;;
  esac
}

main "$@"
