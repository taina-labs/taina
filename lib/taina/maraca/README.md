# Maracá

Identidade e acesso da comunidade.

No código atual:

- setup da Tekoa única e gestão de moradores;
- convites por link/QR, login por nome de usuário e sessões;
- troca e recuperação de senha, tokens de dispositivo e aparelhos;
- papéis `zelador` e `morador`, pedidos e concessões de acesso;
- autorização por `Ypy.Maraca.Policy`, sem atalho da zeladoria para a casa alheia;
- isolamento na aplicação sobre SQLite, sem RLS.

As decisões de produto e o modelo social estão na [arquitetura atual do Tekoá](https://github.com/taina-labs/tekoa/blob/main/tecnico/ARQUITETURA.md). Este README cobre apenas a responsabilidade local do módulo.
