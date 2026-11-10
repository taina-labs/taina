#!/bin/sh
set -eu

repo=$(CDPATH='' cd -P "$(dirname "$0")/../.." && pwd)
bundle=$(mktemp -d "$repo/.compose-smoke.XXXXXX")
bundle=$(CDPATH='' cd -P "$bundle" && pwd)
integration=0
cleanup() {
  status=$?
  trap - EXIT
  if [ "$integration" -eq 1 ]; then
    if [ "$status" -ne 0 ]; then
      compose ps || :
      compose logs --no-color taina || :
    fi
    compose down --volumes >/dev/null 2>&1 || :
  fi
  rm -rf "$bundle"
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

cp "$repo/deploy/compose/compose.yaml" "$bundle/compose.yaml"
cp "$repo/deploy/compose/taina" "$bundle/taina"
cp "$repo/deploy/compose/taina.conf.example" "$bundle/taina.conf.example"
chmod 755 "$bundle/taina"
mkdir "$bundle/backups"
(cd "$bundle" && ./taina init)
[ -f "$bundle/taina.conf" ]
[ -d "$bundle/backups" ]
before=$(cksum "$bundle/taina.conf")
(cd "$bundle" && ./taina init >/dev/null)
after=$(cksum "$bundle/taina.conf")
[ "$before" = "$after" ]

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  docker compose --project-directory "$bundle" --file "$bundle/compose.yaml" config >/dev/null
fi
if [ -n "${TAINA_SMOKE_IMAGE:-}" ]; then
  command -v docker >/dev/null 2>&1 || { printf '%s\n' 'error: Docker is required for integration smoke' >&2; exit 1; }
  docker compose version >/dev/null 2>&1 || { printf '%s\n' 'error: Docker Compose v2 is required for integration smoke' >&2; exit 1; }
  sed "s|image: .*|image: $TAINA_SMOKE_IMAGE|" "$bundle/compose.yaml" >"$bundle/compose.yaml.new"
  mv "$bundle/compose.yaml.new" "$bundle/compose.yaml"
  compose() { docker compose --project-directory "$bundle" --file "$bundle/compose.yaml" "$@"; }
  integration=1
  compose up --detach --wait --wait-timeout 60
  (cd "$bundle" && ./taina config validate)
  (cd "$bundle" && ./taina backup)
  set -- "$bundle"/backups/taina-backup-*.tar.gz
  [ -f "$1" ] || { printf '%s\n' 'error: integration smoke produced no backup' >&2; exit 1; }
  archive=${1##*/}
  compose stop taina
  (cd "$bundle" && ./taina restore "$archive")
  compose down --volumes
  printf '%s\n' 'Compose integration smoke test passed'
else
  printf '%s\n' 'Compose static smoke test passed (set TAINA_SMOKE_IMAGE for Docker integration)'
fi
