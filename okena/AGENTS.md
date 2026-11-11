# Guia dos agents no Okena

Okena é o nome de código; o produto mostrado para as pessoas é sempre **Tainá**.
Código e comentários ficam em inglês. A interface e esta documentação ficam em
pt-BR.

## Escopo atual

O app de produção é Flutter, com alvos iOS e Android. Desktop e web estão fora
do escopo. Para o 1.0.0, implemente o espelho unidirecional do rolo para a
`casa`, com sincronização em background. A validação em simulador iOS e
emulador Android locais é um portão pendente, não um resultado já obtido. Não adicione espelho bidirecional, propagação de exclusões,
armazenamento offline-first, upload resumível, novos endpoints além dos previstos
na arquitetura atual ou redesign sem uma decisão explícita de produto.
`api/openapi.yaml` é o contrato compartilhado com a caixa e não deve ser
reescrito pelo cliente.

## Estrutura

- `api/openapi.yaml`: contrato da API v1 compartilhado com a caixa.
- `design/tokens.css`: espelho dos tokens; não edite aqui.
- `packages/okena_core/`: package Dart puro. API, transporte, modelos
  imutáveis, resultados/erros, fronteiras de sessão, fakes e testes unitários.
- `app/`: app Flutter para iOS/Android. UI por feature, navegação, design
  system, runners nativos, widget tests e smoke contra uma caixa real.

## Arquitetura

- Functional core, imperative shell. Decisões e transformações puras ficam em
  `okena_core` ou em funções isoladas dos ViewModels; IO fica nas bordas.
- O app depende de `TainaApi`, nunca diretamente da implementação real.
  Testes e previews usam `FakeTainaApi`.
- Features consomem autenticação, cache e tratamento de 401/403 através de
  `SessionGateway`, contrato em `app/lib/src/session/`. `SessionModel`
  implementa esse contrato; features não dependem da classe concreta de sessão.
- Transporte e plugins de plataforma ficam atrás de fronteiras abstratas
  explícitas.
- Use `Result<T>`/`TainaResult<T>` para falhas esperadas. Não use exceções como
  fluxo normal de controle. Decodifique e valide JSON na borda do serviço.
- Modelos são imutáveis. Use sealed classes e switches exaustivos do Dart para
  tipos soma. Evite geração de código, a menos que ela realmente se pague.
- A UI segue MVVM: um ViewModel por tela, widgets renderizam estado e encaminham
  eventos. Use `ChangeNotifier`, `ListenableBuilder` e `provider`. Use
  `go_router` para navegação. Não adicione BLoC, Riverpod, GetIt, Freezed ou
  outra forma de gerenciar estado.
- Adicione repositories somente quando eles possuírem estado compartilhado,
  cache, retry ou sincronização. Não crie repository/use case por endpoint.
- Uploads e downloads usam streaming de/para disco. Nunca carregue um arquivo
  inteiro na memória para simplificar multipart ou download.
- Um token de dispositivo pertence a uma comunidade. Nunca reutilize uma sessão
  restaurada sem host nem carregue o token de uma caixa para outra em deep links.

## Limites dos agents

O orquestrador é dono dos arquivos da raiz, de `app/pubspec.yaml`, da
configuração dos runners nativos, da integração e da verificação final. Agents
não podem fazer mutações git, rodar `flutter clean`, atualizar dependências ou
formatar arquivos fora do próprio escopo.

Trabalhe somente nos diretórios atribuídos. Mudanças compartilhadas devem ser
relatadas ao orquestrador com o contrato e o motivo exatos. Não altere o OpenAPI
nem os tokens espelhados diretamente.

## Gates

Cada agent precisa formatar o próprio escopo e rodar as verificações
aplicáveis. É obrigatório terminar sem findings do analyzer e sem testes
falhando ou ignorados. Não marque o trabalho como concluído se houver
comportamento stubado ou se algum gate não tiver sido executado.

- Core: `just core-check`.
- App e features: `just app-check`.
- Integração: `just check`, `just build-ios`, `just build-android` e smoke
  contra uma caixa real quando o fluxo alterar API ou transporte.

Rode `dart format` somente nos caminhos próprios. Preserve estados de
erro/vazio/carregamento, paginação, corridas de deep link, revogação e fluxos
nativos de arquivos/mídia. Uma tela que apenas renderiza não está concluída.
