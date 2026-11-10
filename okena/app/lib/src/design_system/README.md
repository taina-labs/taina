# Design system do app

Este diretório é o design system Flutter do Tainá e espelha
`design/tokens.css`. Os
tokens mantêm os mesmos nomes do CSS, então uma tela pode ser comparada lado a
lado com a versão iOS.

## Como consumir

```dart
import 'package:okena_app/src/design_system/design_system.dart';
```

- `TainaPalette`, `TainaTypography`, `TainaSpacing`, `TainaRadii`,
  `TainaSizes`, `TainaOpacity`, `TainaElevation`: tokens semânticos. Widgets
  não usam `TainaPrimitives`.
- `TainaTheme.data`: `ThemeData` escuro com os padrões de Material alinhados
  aos tokens (scaffold, app bar, diálogo, bottom sheet, snack bar, botões).
- Componentes: `TainaPrimaryButton`, `TainaSecondaryButton`,
  `TainaTextField`, `TainaRowCard`, `TainaZonaBadge`,
  `TainaCleartextNotice`, `TainaEmptyState`, `TainaErrorState`,
  `TainaSkeleton`, `TainaLoadingList`, `TainaText`.
- `TainaFormat`: bytes e datas em pt-BR, sem widgets e sem IO.
- `TainaWords`: as palavras de zona e papel que aparecem na tela.

O tema é único e noturno; o bloco claro de `tokens.css` não é consumido. Não
crie outro gerenciamento de estado: os componentes são
stateless e recebem dados por parâmetro.

## Fontes

As três famílias variáveis e suas licenças OFL estão em `app/assets/fonts/` e
já estão declaradas em `app/pubspec.yaml`:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/fonts/
  fonts:
    - family: Bricolage Grotesque
      fonts:
        - asset: assets/fonts/BricolageGrotesque-Variable.ttf
    - family: Schibsted Grotesk
      fonts:
        - asset: assets/fonts/SchibstedGrotesk-Variable.ttf
    - family: JetBrains Mono
      fonts:
        - asset: assets/fonts/JetBrainsMono-Variable.ttf
```

Os nomes das famílias precisam ser exatamente esses (são as constantes de
`TainaFonts`). Os pesos são aplicados por `FontVariation('wght', ...)` nos
estilos; não declare pesos estáticos nem arquivos duplicados.

## Fiação do tema

O `MaterialApp.router` já usa `TainaTheme.data`. Nenhum outro arquivo do app
precisa mudar para consumir os componentes.

## Verificação

O escopo deste diretório é formatado e testado com:

```sh
dart format app/lib/src/design_system app/test/design_system
just app-check
```
