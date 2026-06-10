# Tainá

## O que é

Tainá é o backend principal do ecossistema de nuvem privada e auto-hospedada. É a base que conecta e coordena todos os serviços da plataforma, permitindo que comunidades tenham controle total sobre seus dados digitais.

## Origem do Nome

Tainá vem do Tupi-Guarani e significa "estrela da manhã" - aquela que guia os viajantes no fim da noite em direção ao amanhecer. Representa o papel do projeto como guia para comunidades que buscam independência digital.

## Funcionalidade

O backend Tainá gerencia:

- Autenticação, convites e autorização de usuários (Maraca)
- Armazenamento de arquivos da comunidade (Ybira)
- Galeria de fotos sobre os arquivos (Jaci-lite)
- Configuração, backup e atualização do sistema
- Chat (Guará), streaming e API JSON para apps cliente são pós-MVP

## Para quem é

- Comunidades que querem controle sobre seus dados
- Grupos que buscam alternativa aos serviços das grandes empresas de tecnologia
- Pessoas interessadas em privacidade digital e auto-hospedagem

## Status do Projeto

Em desenvolvimento ativo, seguindo a [RFC 002](https://github.com/taina-labs/tekoa/blob/main/tecnico/RFC_002_MVP.md).

**MVP:** cofre de arquivos e fotos da comunidade, com instalação plug & play —
uma Tekoa (comunidade) por instância. Documentação completa e guias no
repositório [Tekoá](https://github.com/taina-labs/tekoa).

## Tecnologia

- Elixir 1.20 / OTP 28, Phoenix 1.8
- PostgreSQL 18 com Row-Level Security (isolamento por comunidade)
- Arquitetura de monolito modular, backend-first
- Interface web server-rendered (Phoenix LiveView) na fase de UI
- API JSON pós-MVP para apps cliente (backup de fotos)

## Patrocinadores

Agradeço imensamente aos nossos patrocinadores por apoiar esse projeto!

<p align="center">
  <a href="https://www.coderabbit.ai/?utm_source=oss&utm_medium=github&utm_campaign=zoedsoupe">
    <img src="https://victorious-bubble-f69a016683.media.strapiapp.com/Frame_1686552887_8d2a26b476.svg" alt="Coderabbit Sponsor Logo" height="80"/>
  </a>
</p>

## Contribuindo

Veja o [Guia de Contribuição](https://github.com/taina-labs/tekoa/blob/main/CONTRIBUTING.md) e o [Código de Conduta](https://github.com/taina-labs/tekoa/blob/main/CODE_OF_CONDUCT.md) para saber como participar.

## Licença

Este projeto é licenciado sob [GNU Affero General Public License](LICENSE).
