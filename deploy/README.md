# Deploy do Tainá

Este documento cobre os artefatos locais de deploy. Os guias públicos de instalação e operação ficam no [Tekoá](https://github.com/taina-labs/tekoa).

## Compose

Copie `deploy/compose` para a caixa e execute:

```sh
cd deploy/compose
./taina init
$EDITOR taina.conf
docker compose up --detach --wait
```

O serviço publica `127.0.0.1:4000` e guarda estado nos volumes Docker `taina-data` e `taina-storage`. Backups vão para o diretório do host montado em `/app/backups`, por padrão `./backups`. Use outro disco ou ponto de montagem para recuperação de desastre. A tag da imagem fica fixada em `compose.yaml` e muda com o release.

O Compose controla o ciclo de vida. Use `docker compose stop`, `restart`, `ps`, `logs` e `pull` diretamente. O adaptador encaminha comandos de domínio do release:

```sh
./taina doctor
./taina config validate
./taina backup
./taina account reset-password USERNAME
./taina thumbnails regenerate
```

A restauração é fria e não para nem inicia o serviço sozinha:

```sh
docker compose stop taina
./taina restore ARCHIVE_NAME
docker compose up --detach --wait
```

`taina.conf` é um arquivo de configuração restrito e sem segredos. No primeiro boot, o release cria seu segredo persistente no diretório de dados configurado e o inclui nos backups.

### Docker rootless

No Docker rootless, acrescente `user: "0"` ao serviço `taina` em `compose.yaml`. Nesse modo, o adaptador já executa como root os comandos que tocam o diretório de backup. Mantenha esse diretório pertencendo ao usuário do host.

## NixOS

O flake do Tainá exporta o módulo da aplicação e importa o runtime compartilhado de containers BEAM. Imagem, identidade, diretório de dados, porta e mounts obrigatórios pertencem a `services.beam.containers.taina`; a configuração da aplicação pertence a `services.taina`.

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

O systemd controla o ciclo de vida. Use o comando `taina` configurado apenas para operações de domínio, e `systemctl` ou `journalctl` para o serviço.

## Verificações

`deploy/compose/smoke.sh` executa as verificações estáticas do Compose. Defina `TAINA_SMOKE_IMAGE` com uma imagem local para rodar o teste de integração de backup e restore no Docker.
