# Política de Segurança

## O que o Tainá guarda, e o que isso significa

O Tainá é a nuvem privada de uma comunidade: guarda os arquivos, as fotos e as
contas que aquele grupo resolveu manter para si. Uma falha de segurança aqui
não é um bug de imagem de perfil, é exposição de arquivos de gente.

Por isso o Tainá é AGPL e a segurança é tratada como parte do produto, não como
polimento.

## O que o Tainá **não** promete

Vale ser explícito aqui, porque é a mesma linguagem que a interface usa:

- **Não há criptografia.** Os arquivos são gravados em texto puro no disco. O
  hash SHA-256 do Ybira existe para deduplicação, não para proteção. Quem tem
  acesso físico à caixa, ou acesso root a ela, lê o que está na `casa` de
  qualquer morador.
- **A privacidade da `casa` é promessa de software e confiança.** O zelador
  não tem caminho de leitura no produto, e o software não expõe um, mas não é
  um cadeado matemático. A interface nunca promete o contrário.
- **Só criptografia E2E** no Ybira permitiria dizer honestamente que o zelador
  não consegue ler a casa de ninguém. Isso está no pós-MVP e ainda não existe.

Qualquer relatório que treat a `casa` como criptografada deve ser considerado
um bug de documentação.

## O que já é garantido

- **Isolamento por comunidade via Row-Level Security do PostgreSQL**, com
  `FORCE ROW LEVEL SECURITY`. As políticas são testadas com um role
  não-superuser: o teste de isolamento em `test/taina/rls_isolation_test.exs`
  falha se um contexto de tekoa enxergar dados de outra.
- **Uma comunidade por instância**, com índice único no banco e função de
  context. Não há como criar uma segunda tekoa.
- **Regra de zona (`casa`/`praca`) aplicada em todo caminho de leitura**,
  incluindo o controller de download e o de thumbnail, que era o principal
  vetor de vazamento.
- **Zelador sem autoridade de leitura.** Cuida do disco, dos backups, das
  atualizações e dos convites. Não lê a casa de ninguém.
- **Sessões rotacionadas** no login, com limite de tentativas.
- **Nunca telefonar para casa**: telemetria, métricas e logs ficam na caixa da
  comunidade.

## Reportando uma vulnerabilidade

**Não abra issue pública.** Uma issue aberta entrega o achado a qualquer pessoa
antes de existir correção.

Escreva para **security@taina.dev** (ou por DM para
[@zoedsoupe](https://github.com/zoedsoupe), maintainer do projeto) com:

- o que acontece, e por que você acha que é um problema
- os passos para reproduzir, de preferência em uma instância sua
- a versão da imagem (`docker images ghcr.io/taina-labs/taina`) e o commit
- o que você imagina como impacto, e quem seria afetado

O que acontece depois:

1. Confirmação de recebimento em até 72 horas.
2. Uma estimativa de prazo antes de qualquer correção pública.
3. Correção primeiro, divulgação depois. Avisamos quem reportou antes de
   publicar.
4. Creditamos o reporte no changelog, se isso for confortável para quem
   reportou.

Sem prazo de verdade combinamos com quem reportou. Não tenemos SLA. O que
temos é a obrigação de não sumir.

## Escopo

**No escopo:** qualquer coisa que exponha dados entre moradores, entre
comunidades, ou a não-membros; bypass de autorização ou de RLS; escalonamento
de privilégio de morador para zelador; execução de código; perda ou
corrupção de dados.

**Fora do escopo** (e ainda vale issue normal, é bug não é vulnerabilidade):

- O Taina roda como `nobody` num container, sem criptografia, num aparelho que
  você controla. Quem tem root na caixa tem os arquivos. Isso é o modelo
  documentado, não uma falha.
- Uma comunidade não técnica escolher senha fraca.
- Ausência de rate limiting além do que já existe no login.
- Problemas de navegador ou de acessibilidade sem impacto de segurança.

## Ajudando

O relatório de boa qualidade é o que mais ajuda, mesmo quando não é
vulnerabilidade: passos de reprodução claros, o que você esperava que
acontecesse, e o que aconteceu de fato. Um bom achado sem severidade de
segurança ainda é um bom bug.
