# Site do Tainá

Site público do Tainá: apresentação, demonstração, estado do projeto e a
versão navegável da documentação do Tekoá. O resultado é HTML, CSS e
JavaScript estáticos, sem servidor de aplicação ou rastreamento.

Os textos editoriais ficam em `content/`. Os documentos canônicos continuam no
repositório [Tekoá](https://github.com/taina-labs/tekoa) e são convertidos
durante o build. Não duplique guias em HTML dentro deste diretório.

## Rodar localmente

Na raiz do repositório, com Elixir instalado e o Tekoá disponível localmente:

```sh
elixir site/build.exs --tekoa ../tekoa --output site/_build
python3 -m http.server 8080 --directory site/_build
```

Em um worktree fora da árvore `taina/`, passe o caminho real do checkout do
Tekoá em `--tekoa`. Depois abra `http://localhost:8080`.

O script usa MDEx via `Mix.install`, portanto o primeiro build precisa baixar a
dependência. A aplicação Phoenix, o banco e o Docker não são necessários.

## Conteúdo e rotas

- `pages.exs` lista as páginas editoriais em `content/`.
- `documents.exs` associa cada Markdown publicado do Tekoá à sua rota pública,
  seção e eventuais avisos de contexto.
- `templates/page.html.eex` é a casca comum das páginas.
- Documentos em `tecnico/arquivo/` são publicados como histórico, não como
  descrição do produto atual.

Ao adicionar um documento público ao Tekoá, inclua sua rota em
`documents.exs`. O build reescreve links relativos entre documentos, copia as
mídias necessárias e falha quando encontra referências locais quebradas.

## Testes

Execute:

```sh
elixir site/build_test.exs
```

O teste usa fixtures temporárias e não depende da aplicação Phoenix nem altera
o Tekoá. O diretório `site/_build/` é gerado e não deve ser commitado.

## Publicação

A workflow `.github/workflows/site.yml` testa o gerador, busca a `main` do
Tekoá, gera o site em `site/_build` e publica o artefato no GitHub Pages.

Ela roda em mudanças neste site, a cada seis horas e ao receber o evento
`repository_dispatch` do tipo `tekoa-updated`. Para publicação imediata após
cada mudança no Tekoá, o repositório Tekoá precisa emitir esse evento; a
execução agendada evita depender dessa configuração para eventual sincronia.
O arquivo `CNAME` mantém o domínio `taina.dev.br`.

## Licença

[GNU AGPL v3.0](../LICENSE), a mesma do Tainá.
