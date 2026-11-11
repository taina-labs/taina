# Nhaman

Operação da caixa da comunidade.

No código atual:

- preparação do release e migrações no boot;
- backup local manual ou agendado e restauração fria;
- saúde da comunidade, uso de disco e jobs pendentes;
- verificação de atualização opt-in, sem envio de dados da comunidade;
- comandos de release para backup, restore, senha, configuração e miniaturas.

O 1.0.0 acrescenta backup cifrado off-site com kits de recuperação equivalentes. O backup local continua. E2E no disco local não faz parte desse recurso.

As decisões e o desenho do backup estão na [arquitetura atual do Tekoá](https://github.com/taina-labs/tekoa/blob/main/tecnico/ARQUITETURA.md).
