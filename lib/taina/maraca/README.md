# Maraca

## O que é

Maraca é o serviço de gerenciamento de comunidades e identidades do ecossistema Tainá. É a fundação que conecta pessoas (Avas) às suas comunidades (Tekoas), garantindo autenticação segura, controle de permissões e soberania sobre os dados de cada membro.

## Origem do Nome

Maracá vem do Tupi-Guarani e designa o chocalho cerimonial usado em rituais importantes. Simboliza liderança comunitária, união e a voz coletiva que guia as decisões do grupo. O nome representa o papel central deste serviço como guardião da identidade e organização comunitária.

## Funcionalidade

O Maraca oferece:

- Criação e gerenciamento de Tekoas (comunidades)
- Cadastro seguro de Avas (pessoas/usuários) com criptografia de senhas
- Confirmação de e-mail obrigatória para novos membros
- Sistema de permissões granular por recurso (arquivos, pastas, conversas)
- Controle de acesso baseado em papéis (administrador, membro)
- Isolamento total de dados entre comunidades (Row-Level Security)
- Solicitação de acesso com aprovação explícita (admins não acessam dados sem permissão)
- Lixeira com recuperação de dados excluídos (15 dias configurável)

## Para quem é

- Comunidades que valorizam soberania digital e controle sobre seus dados
- Grupos familiares que querem privacidade e autonomia na gestão de membros
- Coletivos e organizações que precisam de autenticação segura sem depender de Big Tech
- Pessoas que buscam uma alternativa ética aos sistemas centralizados de identidade

## Vantagens

- Usuários são donos de seus dados (admins não têm acesso automático)
- Isolamento completo entre comunidades no nível do banco de dados
- Permissões explícitas e amigáveis para iniciantes
- Padrões seguros por padrão (confirmação de e-mail, criptografia bcrypt)
- Arquitetura extensível para federação entre Tekoas no futuro
- Sem rastreamento, sem venda de dados, sem algoritmos manipulativos

## Status do Projeto

Este projeto está em desenvolvimento ativo. Maraca é o serviço fundamental sobre o qual Ybira (arquivos), Jaci (fotos) e Guará (mensagens) se apoiam para autenticação e autorização.

## Tecnologia

- Autenticação baseada em sessão (Phoenix)
- Criptografia de senhas com bcrypt
- Row-Level Security (RLS) no PostgreSQL para isolamento de dados
- Sistema de permissões com biblioteca Permit
- Confirmação de e-mail com tokens seguros
- Soft delete com recuperação de dados (lixeira)

## Contribuindo

Veja o [Guia de Contribuição](https://github.com/taina-labs/tekoa/blob/main/CONTRIBUTING.md) e o [Código de Conduta](https://github.com/taina-labs/tekoa/blob/main/CODE_OF_CONDUCT.md) para saber como participar.

## Licença

Este projeto é licenciado sob [GNU Affero General Public License](../../../LICENSE).
