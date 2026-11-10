# Site do Tainá

Site público do Tainá, uma nuvem privada e auto-hospedada para uma comunidade.
É HTML, CSS e JavaScript estáticos, sem build ou dependências.

## Rodar localmente

Na raiz do repositório:

```sh
python3 -m http.server 8080 --directory site
```

Depois abra `http://localhost:8080`.

## Publicação

A workflow `.github/workflows/site.yml` publica o diretório `site/` no GitHub
Pages quando seu conteúdo muda na `main`. O arquivo `CNAME` mantém o domínio
`taina.dev.br`.

## Licença

[GNU AGPL v3.0](../LICENSE), a mesma do Tainá.
