# Guias

Esta seção reúne instruções práticas para usar o Tainá e cuidar da caixa. A [Biblioteca](/biblioteca/) guarda decisões do projeto, documentação técnica e arquivos históricos. Os documentos canônicos vêm do repositório Tekoá; um aviso aparece nas páginas cuja fonte precisa de revisão.

## Para moradores

O [guia Começar a usar o Tainá](/guias/comecar/) explica os passos básicos da versão web 0.8.0. O [roteiro Como funciona](/demonstracao/) apresenta os fluxos em mais detalhe. O [glossário](/glossario/) explica os termos usados no portal.

## Para quem cuida da caixa

### Instalação

O guia de instalação está sendo reconciliado com o deploy atual, que usa Compose. A fonte do guia ainda contém instruções antigas para outra forma de instalação. Se você não tem experiência técnica, não siga os comandos antigos como receita. Aguarde a revisão do documento e confira o aviso na página gerada antes de qualquer operação.

Ainda não há um guia de reinstalação atualizado. Não apague volumes, pastas ou dados para tentar reinstalar sem uma cópia verificada e ajuda de alguém com experiência.

Quer avaliar o Tainá para sua comunidade? Escreva para [zoey.spessanha@zeetech.io](mailto:zoey.spessanha@zeetech.io) e conte como vocês guardam arquivos hoje.

- [Guia de instalação](/guias/instalacao/)
- [Guia de hardware](/guias/compras-hardware/)

O guia de hardware contém preços e recomendações antigos. Use-o apenas como referência inicial e confirme informações atuais antes de comprar qualquer equipamento.

### Acesso e recuperação

- [Acesso remoto](/guias/acesso-remoto/): opções para acessar a caixa fora da rede local. O uso de um serviço de terceiros, como Tailscale, pode expor metadados de conexão.
- [Backup e restauração](/guias/runbook-backup-restore/): o documento ainda descreve o fluxo anterior baseado na CLI Oka. A cópia local existe, mas não siga os comandos antigos até a documentação ser reconciliada. A restauração substitui os dados atuais.
- [Recuperação de senha](/guias/runbook-senha/): procedimento para recuperar o acesso à conta.

Não trate uma cópia no mesmo disco da caixa como recuperação contra perda do aparelho. O backup externo cifrado do 1.0.0 ainda não está implementado.

### Ensaios e participação

- [Ensaio do MVP em VM](/guias/ensaio-mvp-vm-macos/): resultados e itens de validação pendentes. Uma VM não certifica o desempenho de um Raspberry Pi.
- [Guia de contribuição](/biblioteca/contribuir/): como propor uma mudança.
- [Código de conduta](/biblioteca/codigo-de-conduta/): acordos para colaboração.
- [Guia de contribuição com GitHub](/biblioteca/contribuir-no-github/): uma opção para quem prefere colaborar pelo GitHub.

As instruções de operação são voltadas a quem cuida da máquina. Se você não sabe se uma ação apaga ou substitui dados, pare e peça ajuda antes de executá-la.
