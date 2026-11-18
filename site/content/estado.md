# Estado atual

O Tainá está na versão **0.8.0**, publicada em 11 de novembro de 2026. O próximo marco é o 1.0.0, com um recorte de captura, armazenamento e recuperação de arquivos e fotos. Não há uma data prometida para esse marco.

## O que o 1.0.0 precisa fechar

- Tornar a zona e a publicação de arquivos mais claras na galeria web e depois do envio.
- Adicionar seleção manual de fotos e captura pela câmera no aplicativo.
- Implementar o espelho unidirecional do rolo de câmera para a casa. Esse recurso ainda não está implementado.
- Implementar um backup cifrado fora da caixa, incremental e restaurável, com kits de recuperação equivalentes. Esse recurso ainda não está implementado.
- Testar a geração de miniaturas JPEG e HEIC no container publicado.

E2E, sincronização nos dois sentidos e propagação de exclusões não fazem parte deste marco.

## O que foi verificado

Instalação e restauração local passaram em teste técnico numa máquina virtual. Isso ainda não prova o uso numa comunidade real, nem a instalação por uma pessoa não técnica ou o funcionamento num Raspberry Pi 5. Atualização e retorno à versão anterior não foram verificados; o backup externo cifrado não foi implementado.

| Área | Situação registrada |
| --- | --- |
| Instalação em VM | Passou com uma pessoa técnica em pouco menos de 20 minutos, incluindo Docker e acesso pela rede privada, sem TLS ou Tailscale. |
| Instalação por pessoa não técnica | Pendente. |
| Recursos limitados da VM | Funcionou bem em avaliação qualitativa. Não é benchmark formal nem certificação de Raspberry Pi 5. |
| Backup e restauração locais | Passaram em ensaio técnico. O exercício por pessoa não técnica ainda está pendente. |
| Atualização e retorno à versão anterior | Não verificados. |
| Aplicativo | Os fluxos principais estão no código. Validar em simulador iOS e emulador Android continua pendente. |
| Backup externo cifrado | Não implementado. |
| Raspberry Pi 5 | Ainda não foi comprado; não há resultado medido nesse equipamento. |
| Pilotos em comunidades | Não verificados. |

O [ensaio em VM](/guias/ensaio-mvp-vm-macos/) registra os resultados e as lacunas. A [documentação completa do roadmap](/estado/roadmap/) detalha o que entra no 1.0.0 e o que está fora dele.

Veja também o [resumo das mudanças recentes](/evolucao/).
