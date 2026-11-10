# OkenaCore

Núcleo Dart puro dos clientes Tainá. É dono da fronteira da API, transporte,
modelos imutáveis, valores de resultado/erro, contratos de sessão, fakes e
testes unitários. Não pode importar Flutter nem plugins de plataforma.

`FakeTainaApi` é a fronteira determinística usada por previews e widget tests
do app.

## O que mora aqui

- `lib/src/result.dart`: `TainaResult<T>`, `Ok`/`Err`, `map`, `fold`, `then`.
- `lib/src/taina_error.dart`: erros esperados como valor, inclusive o
  envelope da API (`ApiError`) e o problema de endereço.
- `lib/src/json/`: leitura tipada na borda e `JsonValue` para o payload livre
  do mural. Um corpo inválido vira `InvalidResponseError`.
- `lib/src/models/`: todos os modelos imutáveis da API v1, com `fromJson`
  explícito. `FileRecord` evita colidir com o `File` de `dart:io` em qualquer
  consumidor.
- `lib/src/session/`: `Session`, `Me`, contratos `SessionStorage` e
  `HostStore`, `SessionStore` e as implementações em memória. Keychain,
  Keystore e SharedPreferences ficam no app, atrás destes contratos.
- `lib/src/api/`: `TainaApi`, `LiveTainaApi`, `FakeTainaApi`,
  `InstanceAddress`, `MultipartBody`, `Sort` e `ConditionalStore`.
- `lib/src/transport/`: a fronteira `Transport` e `IoTransport`, a
  implementação de produção sobre `dart:io`. Upload e download passam por
  arquivo em disco; um vídeo grande nunca é carregado inteiro na memória.
- `lib/src/media/thumbnail_store.dart`: cache limitado em memória, por rkey e
  tamanho. Falha não é cacheada.
- `bin/okena_smoke.dart`: smoke executável da API contra uma caixa real.

## Smoke

Contra uma caixa de verdade:

```sh
dart run okena_core:okena_smoke http://taina.yby --user ana --password segredo
dart run okena_core:okena_smoke http://taina.yby --user ana --password segredo --write
```

Sem `--write` o smoke só lê: instância, sessão, `me`, pastas e a raiz. Com
`--write` ele cria `pasta-do-smoke`, sobe `teste-do-smoke.txt`, lê de volta e
confirma que um texto não tem miniatura. O token do aparelho nunca é impresso.

## Dependências

Nenhuma em runtime. Transporte usa `dart:io`, JSON usa `dart:convert`. O
package é só para iOS e Android, então não há alvo web que justifique outra
biblioteca HTTP.

## Verificações

Na raiz do repositório:

```sh
just core-check
```

O gate roda `dart analyze` e `dart test`. Não deve haver finding nem teste
falhando ou ignorado. Formate só os caminhos deste package:

```sh
dart format packages/okena_core/lib packages/okena_core/bin packages/okena_core/test
```
