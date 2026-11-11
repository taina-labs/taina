# Okena

Okena é o nome de código do app Tainá. O produto mostrado para as pessoas é sempre **Tainá**.

## Estrutura

- `api/openapi.yaml`: link para `priv/static/openapi.yaml` no mesmo monorepo.
- `packages/okena_core/`: núcleo Dart puro, API, modelos, transporte, fakes e testes.
- `app/`: app Flutter para iOS e Android.
- `design/tokens.css`: espelho dos tokens da caixa.

Bundle iOS e application id Android: `io.taina.app`.

## Estado e escopo

O app atual cobre a API v1: sessão por token de dispositivo, pessoas, pastas e arquivos, lixeira, fotos, mural, pedidos e concessões, armazenamento e saúde. Tem telas de setup, login, aceite de convite e redefinição de senha, além de deep links `taina://`, paginação e polling em foreground.

O 1.0.0 adiciona:

- seleção manual da galeria e captura pela câmera;
- espelho unidirecional do rolo para a `casa`, em iOS e Android;
- fila com retry, progresso, deduplicação e pausas compreensíveis;
- validação em simulador iOS e emulador Android locais.

Não entram espelho bidirecional, propagação de exclusões, publicação automática na `praça`, offline-first ou E2E. As regras completas estão na [arquitetura do Tekoá](https://github.com/taina-labs/tekoa/blob/main/tecnico/ARQUITETURA.md).

## Autenticação

`POST /api/v1/session` recebe usuário e senha e devolve um token `tnd_...` uma única vez. O app guarda o token no armazenamento seguro do aparelho e envia `Authorization: Bearer <token>`. Revogação vale na requisição seguinte.

Um token pertence a uma comunidade. Ao abrir um link de outra caixa, a sessão anterior é limpa antes da troca de host.

## Rodar e verificar

```sh
just check          # analyzer e testes do core e do app
just build-ios      # simulador, sem assinatura
just build-android  # APK debug
```

Para iniciar nos ambientes locais:

```sh
just run ios
just run android
```

Os ids padrão ficam no `justfile`. O esquema `taina://` está registrado nos dois runners para convites e redefinição de senha.

## Smoke contra uma caixa

```sh
cd packages/okena_core
dart run bin/okena_smoke.dart http://localhost:4000 --user ana --password segredo
```

Sem `--write`, o smoke só lê. Com `--write`, ele cria uma pasta, sobe um arquivo, baixa e confere os bytes:

```sh
dart run bin/okena_smoke.dart http://localhost:4000 \
  --user ana --password segredo --write
```

O token não é impresso.

## Regras técnicas

As fronteiras e os gates de contribuição estão em `AGENTS.md`. O app depende do contrato `TainaApi`; testes e previews usam `FakeTainaApi`. O núcleo não conhece plugins de plataforma, e uploads/downloads grandes usam streaming.

## Licença

AGPL-3.0, a mesma do Tainá. Veja `LICENSE`.
