# Ybira

## O que é

Ybira é o serviço de armazenamento e gerenciamento de arquivos do ecossistema Tainá. Os dados ficam no armazenamento local configurado para a caixa da comunidade.

## Origem do Nome

Ybira vem do Tupi-Guarani e significa "árvore" ou "madeira". O nome simboliza as raízes profundas, o crescimento constante e a solidez de uma base que sustenta e protege tudo que é importante para a comunidade.

## Funcionalidade

O Ybira oferece:

- Upload e download de arquivos
- Organização em pastas
- Compartilhamento com controle de acesso
- Áreas casa e praça, com leitura conforme as permissões da comunidade
- Lixeira com restauração por até 30 dias antes do expurgo
- Controle de uso e cota de armazenamento por comunidade
- Geração de thumbnails para imagens quando o formato é suportado pela caixa

Uploads respeitam a cota configurada para a comunidade. Se a cota não estiver configurada, o sistema não aplica um limite próprio; o espaço disponível no disco continua sendo um limite prático.

## Para quem é

- Comunidades que precisam compartilhar arquivos com regras claras de acesso
- Grupos que querem alternativa aos serviços de armazenamento comerciais
- Pessoas que valorizam controle sobre seus documentos pessoais

## Vantagens

- Os arquivos ficam na caixa da comunidade, não em servidor de terceiro
- Sem taxas mensais recorrentes
- Controle sobre quem acessa os arquivos

## Como funciona

Arquivos novos ficam na área casa. Um morador pode publicar um arquivo na praça para compartilhá-lo com a comunidade. Arquivos na lixeira continuam ocupando espaço até serem restaurados ou expurgados. O expurgo após 30 dias devolve a cota; os bytes podem ser removidos depois pelo coletor de blobs, se nenhum arquivo ainda os referenciar.

## Status do Projeto

Este projeto está em desenvolvimento ativo. A documentação completa e guias de instalação estão disponíveis no repositório [Tekoá](https://github.com/taina-labs/tekoa).

## Tecnologia

- Interface web server-rendered com Phoenix LiveView
- Armazenamento de blobs no disco da caixa
- Autorização e isolamento por comunidade aplicados pela aplicação
- Thumbnails de imagem gerados em segundo plano quando há suporte ao formato

## Contribuindo

Veja o [Guia de Contribuição](https://github.com/taina-labs/tekoa/blob/main/CONTRIBUTING.md) e o [Código de Conduta](https://github.com/taina-labs/tekoa/blob/main/CODE_OF_CONDUCT.md) para saber como participar.

## Licença

Este projeto é licenciado sob [GNU Affero General Public License](../../../LICENSE).
