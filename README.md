# Tainá

Código da nuvem privada e auto-hospedada de uma comunidade. Uma caixa guarda os arquivos e as fotos do grupo, sem depender de uma nuvem comercial para usá-los no dia a dia.

A documentação de produto, os guias e o roadmap vivem no [Tekoá](https://github.com/taina-labs/tekoa), a fonte de verdade do projeto.

## Neste repositório

- Interface web Phoenix LiveView.
- API JSON v1, documentada em `priv/static/openapi.yaml`.
- App Flutter para iOS e Android em `okena/`.
- Contextos Maracá, Ybira, Jaci e Nhaman, com o núcleo Ypy interno em `lib/ypy`.
- Deploy Compose e NixOS em `deploy/`.

## Stack

Elixir 1.20/OTP 28, Phoenix 1.8, SQLite/WAL, Oban, libvips e Flutter. Não há PostgreSQL nem RLS; autorização e isolamento ficam na aplicação.

## Desenvolvimento

```sh
mix setup
mix test
mix precommit
```

O app tem seus próprios comandos em `okena/justfile`:

```sh
cd okena
just check
just build-ios
just build-android
```

As instruções de arquitetura e contribuição técnica estão em `AGENTS.md` e `okena/AGENTS.md`.

## Documentação

- [Estado e roadmap](https://github.com/taina-labs/tekoa/blob/main/ROADMAP.md)
- [Arquitetura atual](https://github.com/taina-labs/tekoa/blob/main/tecnico/ARQUITETURA.md)
- [Guias de instalação e operação](https://github.com/taina-labs/tekoa#guias-do-operador)
- [Deploy deste repositório](deploy/README.md)
- [Segurança e privacidade](SECURITY.md)

## Licença

[GNU Affero General Public License v3.0](LICENSE).
