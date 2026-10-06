# Tainá

## O que é

Tainá é o backend principal do ecossistema de nuvem privada e auto-hospedada. É a base que conecta e coordena todos os serviços da plataforma, permitindo que comunidades tenham controle total sobre seus dados digitais.

## Origem do Nome

Tainá vem do Tupi-Guarani e significa "estrela da manhã" - aquela que guia os viajantes no fim da noite em direção ao amanhecer. Representa o papel do projeto como guia para comunidades que buscam independência digital.

## Funcionalidade

O backend Tainá gerencia:

- Autenticação, convites e autorização de usuários (Maraca)
- Armazenamento de arquivos da comunidade (Ybira)
- Galeria de fotos sobre os arquivos (Jaci-lite)
- Configuração, backup e atualização do sistema
- Chat (Guará), streaming e API JSON para apps cliente são pós-MVP

## Para quem é

- Comunidades que querem controle sobre seus dados
- Grupos que buscam alternativa aos serviços das grandes empresas de tecnologia
- Pessoas interessadas em privacidade digital e auto-hospedagem

## Status do Projeto

Em desenvolvimento ativo, seguindo a [RFC 002](https://github.com/taina-labs/tekoa/blob/main/tecnico/RFC_002_MVP.md).

**MVP:** cofre de arquivos e fotos da comunidade, com instalação plug & play —
uma Tekoa (comunidade) por instância. Documentação completa e guias no
repositório [Tekoá](https://github.com/taina-labs/tekoa).

O [roadmap](https://github.com/taina-labs/tekoa/blob/main/ROADMAP.md) diz o que
está pronto e o que ainda falta para o `0.1.0`, separado entre bloqueadores de
lançamento e o que é apenas recomendado.

## Tecnologia

- Elixir 1.20 / OTP 28, Phoenix 1.8
- PostgreSQL 18 com Row-Level Security (isolamento por comunidade)
- Arquitetura de monolito modular, backend-first
- Interface web server-rendered (Phoenix LiveView) na fase de UI
- API JSON pós-MVP para apps cliente (backup de fotos)

## Instalação e operação

Este repositório é o código do Tainá. Para subir um servidor numa caixa
(Raspberry Pi, mini PC ou VPS), use o [Oka](https://github.com/taina-labs/oka),
o repositório de orquestração: ele baixa a imagem publicada e sobe tudo com um
comando (`./install.sh`), com HTTPS automático via Caddy e atualização em um
passo (`./update.sh`).

O passo a passo do zero, para quem nunca fez isso, está no
[guia de instalação](https://github.com/taina-labs/tekoa/blob/main/guias/instalacao.md).

A imagem multi-arch (amd64 e arm64 para o Raspberry Pi 5) é publicada em
`ghcr.io/taina-labs/taina` a cada release. Até a primeira release existir, dá
para montar a imagem na própria caixa a partir do código: o
`build-image.sh` do Oka faz isso e escreve um `docker-compose.override.yml`
que o Compose lê sozinho.

Guias do operador (no repositório [Tekoá](https://github.com/taina-labs/tekoa)):

- Instalação (do zero, em menos de 30 minutos): `guias/instalacao.md`.
- Acesso remoto (Tailscale recomendado, Headscale soberano, WireGuard avançado):
  `guias/acesso-remoto.md`.
- Runbook de backup e restauração (procedimento e ensaio): `guias/runbook-backup-restore.md`.
- Hardware e montagem: `guias/compras-hardware.md`.

## Patrocinadores

Agradeço imensamente aos nossos patrocinadores por apoiar esse projeto!

<p align="center">
  <a href="https://www.coderabbit.ai/?utm_source=oss&utm_medium=github&utm_campaign=zoedsoupe">
    <img src="https://victorious-bubble-f69a016683.media.strapiapp.com/Frame_1686552887_8d2a26b476.svg" alt="Coderabbit Sponsor Logo" height="80"/>
  </a>
</p>

## Contribuindo

Veja o [Guia de Contribuição](https://github.com/taina-labs/tekoa/blob/main/CONTRIBUTING.md) e o [Código de Conduta](https://github.com/taina-labs/tekoa/blob/main/CODE_OF_CONDUCT.md) para saber como participar.

## Licença

Este projeto é licenciado sob [GNU Affero General Public License](LICENSE).
