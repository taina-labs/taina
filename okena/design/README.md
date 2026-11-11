# design

Este diretório espelha os tokens do Tainá.

`tokens.css` é cópia exata de `assets/css/tokens.css` do repositório `taina`.
Aquele arquivo é, por sua vez, o espelho 1:1 do Penpot ("Cofre da Comunidade -
UI v1"), que é a fonte da verdade do visual. A ordem é essa:

    Penpot  ->  taina/assets/css/tokens.css  ->  okena/design/tokens.css

Nada aqui se inventa. Um valor novo nasce no Penpot, desce para o CSS do Tainá e
só então chega aqui.

## Forma

Dois níveis, como no Penpot: **primitivos** (paleta e escala cruas) e
**semânticos** (o que os componentes consomem). Componente nunca usa primitivo
direto; se um valor novo for preciso, ele nasce primeiro como token semântico.

O tema é único e noturno; não há bloco claro nem `prefers-color-scheme` no app.
Cada subsistema tem seu acento de serviço (`--service-ybira` floresta, `--service-jaci` lua,
`--service-maraca` ember, `--service-nhaman` céu), que se usa, não se recolore.
As fontes são fixas: Bricolage Grotesque (display), Schibsted Grotesk (corpo) e
JetBrains Mono (mono).

## Como usar

O app não consome CSS diretamente. O design system Flutter deriva deste arquivo
as cores, o espaçamento, os raios e a tipografia, mantendo os mesmos nomes de
token (`surface-default`, `brand-primary`, `text-muted`, `size-touch`) para que
uma tela possa ser comparada com a web lado a lado.

## Sincronia

O espelho é exato, então a checagem de drift é um `diff` entre os dois arquivos,
com os repositórios lado a lado:

    diff okena/design/tokens.css taina/assets/css/tokens.css

Sem saída, estão em dia.
