# Okena

Okena (Tupi-Guarani: porta, entrada; ok = casa) é o código do app do Tainá.
Tainá é o produto: é o nome que a pessoa vê, busca na loja e lê na interface.
Okena nunca aparece para quem usa.

## O que vive aqui

    api/openapi.yaml       o contrato da API JSON v1, compartilhado com o backend
    packages/okena_core/   o núcleo Dart puro do app
    app/                   o app Flutter para iOS e Android
    design/                os tokens espelhados do Penpot

Bundle iOS e application id Android: `io.taina.app`.

## O contrato

`api/openapi.yaml` aponta para o documento OpenAPI 3.0.3 completo mantido no
repositório do box. Ele cobre a superfície inteira do v1: sessão por token de
dispositivo, pessoas, pastas e arquivos (com upload, download e miniatura),
lixeira, fotos, mural, pedidos de acesso, armazenamento e saúde.

Os `components` espelham o arquivo do kernel (`ypy/api/openapi.components.yaml`),
que é a fonte única das formas de record (zona, papel, envelope de erro,
paginação) e que o kernel protege com um teste de conformidade. Os `paths` são
do box e vivem na tabela da `RFC_005_API_E_APP.md`, no repositório `tekoa`.
Quando o kernel muda uma forma, este espelho muda junto.

## Autenticação

O app não usa sessão de cookie. Ele entra em `POST /api/v1/session` com usuário
e senha e recebe um token de dispositivo (`tnd_...`) uma única vez; guarda no
armazenamento seguro do aparelho (Keychain no iOS e keystore no Android) e manda
em `Authorization: Bearer <token>`. A revogação, pela própria pessoa ou pela
zeladora, vale na requisição seguinte.

Um token pertence a uma comunidade. Ao abrir um link para outra caixa, o app
limpa a sessão anterior antes de trocar o endereço, para não enviar a
credencial de uma comunidade à outra.

## Regras que o app respeita

- **casa** é privada por padrão: cada pessoa concede leitura explicitamente.
- **praça** é partilhada por norma; colocar algo lá é o próprio consentimento.
- A **zeladora** cuida da máquina e não tem atalho para a casa de ninguém.
- Um box serve **uma** comunidade: sem troca de comunidade, sem feed entre
  instâncias.

## Rodar e verificar

O app usa Flutter MVVM, `provider` e `go_router`. O núcleo é um package Dart
puro, independente do Flutter e dos plugins de plataforma.

```bash
just check          # analyzer e testes do core e do app
just build-ios      # build para simulador, sem assinatura
just build-android  # APK debug
```

Os recipes `just core-check` e `just app-check` verificam cada package
separadamente. Para rodar o app num emulador:

```bash
just run ios            # simulador iOS padrão
just run ios <udid>     # simulador específico
just run android        # AVD padrão
just run android <id>   # AVD ou device id (emulator-5554)
```

Os ids padrão ficam no `justfile`; o emulador precisa estar bootado.

Os runners nativos ficam em `app/ios` e `app/android`. O esquema `taina://` está
registrado nos dois para convites e redefinição de senha. Exemplos de deep link
em desenvolvimento:

```bash
# iOS Simulator
xcrun simctl openurl booted "taina://convite/TOKEN?host=http%3A%2F%2Flocalhost%3A4000"

# Android emulator/device
adb shell am start -a android.intent.action.VIEW \
  -d "taina://convite/TOKEN?host=http%3A%2F%2F10.0.2.2%3A4000" io.taina.app
```

No Android Emulator, `10.0.2.2` alcança o `localhost` da máquina hospedeira.

## Conferir contra uma caixa de verdade

O core traz um smoke executável que percorre a fatia mínima da API pela mesma
camada que o app usa. É a forma mais rápida de saber se o problema é da caixa ou
do cliente:

```bash
cd packages/okena_core
dart run bin/okena_smoke.dart http://localhost:4000 --user ana --password segredo
```

Sem `--write` ele só lê. Com `--write` ele cria a pasta `pasta-do-smoke`, sobe
`teste-do-smoke.txt`, baixa de volta e confere os bytes, pede a miniatura (que
um texto não tem) e diz o que deixou na comunidade:

```bash
dart run bin/okena_smoke.dart http://localhost:4000 \
  --user ana --password segredo --write
```

O token do aparelho nunca é impresso.

## O que já existe

O `OkenaCore` cobre a API v1 inteira: instância e sessão por token de
dispositivo, quem está agindo, dispositivos, pessoas, pastas e arquivos (subir,
baixar, miniatura, renomear, mover, trocar de zona, apagar), lixeira, fotos,
mural, pedidos de acesso, armazenamento e saúde, mais o aceite de convite e a
redefinição de senha por deep link. Um método em `TainaApi` por endpoint.

O app tem as telas de Setup, Login, Início, Arquivos (com a lixeira), Fotos,
Mural, Moradores, Armazenamento, Saúde, Pedidos, Conta, e as de aceite de
convite e de redefinição de senha. Um ViewModel por tela, decisões em funções
puras, previews e testes contra `FakeTainaApi`.

As três fontes da marca vêm empacotadas em `app/assets/fonts`: os TTF variáveis
das mesmas famílias que a web auto-hospeda, com a licença OFL de cada uma. O
eixo `wght` é o mesmo nas duas pontas.

Falta: a arte final da tela de abertura e dos ícones dos apps.

## Licença

AGPL-3.0, a mesma do Tainá. Veja `LICENSE`.
