# App Flutter do Tainá

Este é o app iOS/Android do Tainá. A implementação usa Flutter MVVM,
`provider`, `go_router` e o package Dart puro `okena_core`, em
`../packages/okena_core`.

## Verificações

Na raiz do repositório:

```sh
just app-check
just build-ios
just build-android
```

O recipe `just check` verifica o app e o core. Consulte `../AGENTS.md` para a
arquitetura, os limites de contribuição e os gates.
