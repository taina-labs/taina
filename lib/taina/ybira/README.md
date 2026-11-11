# Ybira

Armazenamento e gestão dos arquivos da comunidade.

No código atual:

- upload, download, pastas, renomear, mover e excluir;
- zonas `casa` e `praça`, concessões e leitura autorizada em todos os caminhos;
- blobs no disco, hashes, cotas e coleta de objetos sem referência;
- lixeira com restauração e expurgo após 30 dias;
- miniaturas em background quando a caixa suporta o formato.

Novos arquivos nascem na `casa`. O espelho do rolo previsto para o 1.0.0 também escreve somente nela e nunca publica automaticamente na `praça`.

As regras vigentes estão na [arquitetura atual do Tekoá](https://github.com/taina-labs/tekoa/blob/main/tecnico/ARQUITETURA.md).
