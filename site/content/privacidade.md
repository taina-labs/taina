# Privacidade e limites

O Tainá foi feito para guardar os dados na caixa escolhida pela comunidade. Isso reduz a dependência de uma nuvem central do projeto, mas não elimina a confiança em quem hospeda, cuida ou conecta a caixa.

## A casa protege por regra do programa

Arquivos locais não são cifrados. A casa limita o que cada pessoa consegue abrir pela interface do Tainá. Um zelador não recebe acesso automático à casa de outra pessoa. Porém, quem tem acesso root, isto é, controle total do sistema operacional da caixa, pode ler os arquivos no disco.

HTTPS protege a comunicação entre navegador e caixa contra leitura no caminho. HTTPS não cifra os arquivos no disco e não é criptografia de ponta a ponta.

## Dados que ficam na caixa e serviços externos

O Tainá não envia telemetria, métricas ou logs para um serviço central do projeto. Esses dados ficam na caixa. Este site é estático, não inclui ferramenta de análise de visitas e não usa cookies. O provedor que entrega o site ainda pode processar dados técnicos da conexão, conforme suas próprias regras.

As escolhas de hospedagem e conexão têm limites diferentes:

- **Servidor alugado:** o provedor controla o computador físico e pode ter acesso administrativo à máquina virtual. Consulte os termos do fornecedor escolhido.
- **Tailscale:** segundo o guia de acesso remoto, o serviço de coordenação vê metadados como nomes dos aparelhos e horários de conexão. O conteúdo dos arquivos não passa legível pelo plano de controle. A comunidade escolhe se aceita essa dependência.
- **Backup externo cifrado:** está planejado para o 1.0.0, mas ainda não foi implementado. Quando existir, a cifra protege a cópia contra o provedor externo. O volume agregado e os horários continuam visíveis. Isso não protege os arquivos locais nem impede root de ler a caixa.

Veja os detalhes no [guia de acesso remoto](/guias/acesso-remoto/) e no [roadmap](/estado/roadmap/).

## O que não faz parte do plano atual

Criptografia de ponta a ponta, ou E2E, não está no escopo atual nem na fila do 1.0.0. Não a tratamos como um recurso prometido para depois.

O Tainá não promete conformidade total com a LGPD. A comunidade que opera a caixa precisa entender suas responsabilidades e as regras do provedor escolhido. Ainda falta trabalho formal, como definir processos de atendimento a pedidos, resposta a incidentes e documentos de privacidade revisados.

Para conversar sobre privacidade ou apontar uma informação incorreta, escreva para [zoey.spessanha@zeetech.io](mailto:zoey.spessanha@zeetech.io).
