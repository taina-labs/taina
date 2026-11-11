# Segurança e privacidade

O Tainá guarda arquivos, fotos e contas de uma comunidade. Uma falha de segurança pode expor dados de pessoas reais. Segurança faz parte do produto, não é polimento.

## O que o Tainá não promete

- **A casa local não é cifrada.** Arquivos são gravados em texto puro. SHA-256 serve para deduplicação, não para proteção. Quem tem acesso físico ou root na caixa pode lê-los.
- **A privacidade da casa é promessa de software e confiança.** A zeladoria não tem caminho de leitura pelo produto, mas isso não é uma garantia criptográfica contra o host.
- **E2E não está no escopo atual.** O backup externo cifrado do 1.0.0 protege a cópia contra o provedor; não cifra o disco local nem muda o poder de root.

Documentação que apresentar a casa local como criptografada está errada e deve ser corrigida.

## Garantias implementadas

- Uma comunidade por instância, com enforcement no contexto e no banco.
- SQLite com isolamento e autorização na aplicação. Não há PostgreSQL nem RLS.
- A varredura `test/taina/isolation_sweep_test.exs` cobre a regra de leitura nos contexts, controllers e telas.
- Regra `casa`/`praça` aplicada também a metadados, downloads e miniaturas.
- Zeladoria sem autoridade de leitura sobre a casa de outra pessoa.
- Sessões rotacionadas e limite de tentativas de login.
- Tokens de dispositivo revogáveis, guardados como hash no banco.
- Telemetria, métricas e logs permanecem na caixa.

## Privacidade e LGPD

Este é um projeto de código aberto e auto-hospedado. A mantenedora não coleta, armazena, acessa ou processa dados pessoais, arquivos, metadados ou logs das instâncias.

Os dados permanecem na caixa da comunidade. Quando ela configurar o backup externo, uma cópia cifrada também ficará no destino que escolher. Nenhum desses caminhos envia dados à mantenedora por default.

A conformidade com a Lei Geral de Proteção de Dados (Lei 13.709/2018) e com outras regulações é responsabilidade de quem hospeda e gerencia a instância:

- no uso estritamente pessoal e sem fins econômicos, verifique as condições do art. 4º da LGPD;
- no uso comunitário, comercial ou institucional, a pessoa ou organização operadora precisa cuidar de base legal, consentimento, políticas e segurança do servidor.

O software é fornecido no estado em que se encontra, sem garantia de segurança absoluta contra invasões, vazamentos ou configuração incorreta.

## Reportar uma vulnerabilidade

**Não abra issue pública.** Escreva para [zoey.spessanha@zeetech.io](mailto:zoey.spessanha@zeetech.io) ou contate [@zoedsoupe](https://github.com/zoedsoupe) por DM.

Inclua, quando possível:

- impacto e quem seria afetado;
- passos para reproduzir numa instância própria;
- versão da imagem e commit;
- logs relevantes, sem dados pessoais ou segredos.

Não há SLA. Recebimento, correção e divulgação são combinados com quem reportou. A correção vem antes da divulgação pública, e o crédito é opcional.

## Escopo de segurança

**No escopo:** exposição de dados entre moradores ou a não-membros; bypass de autorização ou isolamento; escalonamento de privilégio; execução de código; perda ou corrupção de dados; falha na cifra ou na verificação de backup.

**Bug normal, não vulnerabilidade por si só:** acesso root num aparelho controlado pela comunidade, senha fraca escolhida pela comunidade, ausência de rate limiting fora dos fluxos já protegidos e problemas sem impacto de segurança.
