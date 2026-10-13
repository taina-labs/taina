# Jaci

> **MVP como "Jaci-lite".** O MVP entrega grade, linha do tempo e visualização
> em tela cheia sobre os arquivos do Ybira. Álbuns, reconhecimento facial e
> backup automático do celular são pós-MVP. Ver
> [RFC 002](https://github.com/taina-labs/tekoa/blob/main/tecnico/RFC_002_MVP.md).

## O que é

Jaci é a galeria de fotos e vídeos da comunidade. É uma camada de leitura sobre os arquivos que o Ybira guarda: não guarda cópia própria nem altera nada.

## Origem do Nome

Jaci vem do Tupi-Guarani e significa "lua". Na mitologia indígena, Jaci é a divindade associada à memória, aos ciclos da vida e à preservação das histórias. O nome representa a importância de guardar e organizar nossas memórias mais preciosas.

## Funcionalidade

O Jaci oferece:

- Grade de fotos e vídeos com scroll infinito
- Linha do tempo agrupada por dia (data do EXIF quando houver, senão a data de upload)
- Thumbnails em dois tamanhos, gerados pelo Ybira
- Visualização em tela cheia
- Leitura que respeita as zonas casa e praça e as permissões explícitas

## Para quem é

- Famílias que querem preservar memórias com segurança
- Pessoas que valorizam privacidade das próprias fotos
- Grupos que buscam alternativa aos serviços de fotos comerciais

## Vantagens

- As fotos ficam na caixa da comunidade, não em servidor de terceiro
- Sem envio de dados para empresas
- Qualidade original preservada, sem compressão forçada

## Status do Projeto

Em desenvolvimento ativo, seguindo a [RFC 002](https://github.com/taina-labs/tekoa/blob/main/tecnico/RFC_002_MVP.md). Documentação e guias no repositório [Tekoá](https://github.com/taina-labs/tekoa).

## Tecnologia

- Interface web server-rendered (Phoenix LiveView)
- Camada de leitura sobre o Ybira, sem armazenamento próprio
- Thumbnails gerados pelo Ybira (libvips)

## Contribuindo

Veja o [Guia de Contribuição](https://github.com/taina-labs/tekoa/blob/main/CONTRIBUTING.md) e o [Código de Conduta](https://github.com/taina-labs/tekoa/blob/main/CODE_OF_CONDUCT.md) para saber como participar.

## Licença

Este projeto é licenciado sob [GNU Affero General Public License](../../../LICENSE).
