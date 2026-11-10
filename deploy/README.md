# Taina deployment

## Compose

Copy `deploy/compose` to the box, then run:

```sh
cd deploy/compose
./taina init
$EDITOR taina.conf
docker compose up --detach --wait
```

The service publishes `127.0.0.1:4000` and stores state in the named Docker
volumes `taina-data` and `taina-storage`. Backups go to the host directory bound
to `/app/backups`, `./backups` by default. Put it on a separate disk or mount for
disaster recovery. The image tag is pinned in `compose.yaml` and updated with
the server release.

Compose owns lifecycle. Use `docker compose stop`, `restart`, `ps`, `logs` and
`pull` directly. The adapter forwards release domain commands:

```sh
./taina doctor
./taina config validate
./taina backup
./taina account reset-password USERNAME
./taina thumbnails regenerate
```

Restore is deliberately cold and never stops or starts the service itself:

```sh
docker compose stop taina
./taina restore ARCHIVE_NAME
docker compose up --detach --wait
```

`taina.conf` is a strict, non-secret configuration file. The release creates its
persistent secret under the configured data directory on first boot and includes
it in backups.

### Rootless Docker

Under rootless Docker, add `user: "0"` to the `taina` service in `compose.yaml`.
The adapter already runs commands that touch the backup directory as root in
that mode. Keep the backup directory owned by your host user.

## NixOS

The Taina flake exports the application module and imports the shared BEAM
container runtime. Image, identity, data directory, port and required mounts
belong to `services.beam.containers.taina`; application configuration belongs to
`services.taina`.

```nix
inputs.taina.url = "github:taina-labs/taina/v0.7.1";

services.beam.containers.taina = {
  enable = true;
  image = "ghcr.io/taina-labs/taina:v0.7.1";
  uid = 993;
  gid = 993;
  port = 4000;
  dataDir = "/var/lib/taina";
};

services.taina = {
  hostname = "community.example.org";
  storageDir = "/var/lib/taina-storage";
  backupDir = "/var/lib/taina-backups";
  backup.enable = true;
};
```

Systemd owns lifecycle. Use the configured `taina` command only for domain
operations and `systemctl` or `journalctl` for service operations.

## Checks

`deploy/compose/smoke.sh` runs the static Compose checks. Set `TAINA_SMOKE_IMAGE`
to a locally built image to run the Docker backup and restore integration test.
