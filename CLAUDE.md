# CLAUDE.md — Tainá

Project memory for the Tainá app (this git repo). Overrides the user-level `~/.claude/CLAUDE.md` where they conflict. The workspace-level `../CLAUDE.md` is just a pointer to this file, to `AGENTS.md`, and to the `community-ux-reviewer` agent.

## Source of truth: `../tekoa/`

**`../tekoa/` is the canonical documentation and the source of truth for this project.** Before proposing architecture, scope, or behavior, read the relevant doc in `../tekoa/` and align to it. If code and `../tekoa/` disagree, `../tekoa/` wins — surface the drift rather than inventing a third answer.

- `../tekoa/ROADMAP.md` — current MVP roadmap (v3.0). What's in/out of scope, and ordering. **Check this before suggesting features.**
- `../tekoa/tecnico/RFC_ARQUITETURA.md` — the full architecture RFC. The authority on structure and subsystem boundaries.
- `../tekoa/tecnico/RFC_002_MVP.md` — the MVP RFC that supersedes the older "PWA Monolith" v2.0 design; holds the rationale for current decisions.
- `../tekoa/guias/contribuindo-github.md` — contribution workflow.
- `../tekoa/CONTRIBUTING.md`, `../tekoa/CODE_OF_CONDUCT.md` — process and conduct.

`../tekoa/` is a separate docs repo (`taina-labs/tekoa`) checked out as a sibling at the workspace root — it is **not** part of this app repo. Do not edit it as a side effect of app work; doc changes are deliberate and go through the docs repo.

## What Tainá is

Self-hosted private-cloud platform — a community's file/photo vault with painless install (per `ROADMAP.md`). Modular monolith, backend-first. AGPL. Tupi-Guarani-named subsystems: **Maracá** (auth/invites/authz), **Ybira** (content-addressed storage, source of truth for all file services — extend by composition, not inheritance), **Jaci** (photo gallery), **Guará** (chat, post-MVP).

## Stack

- Elixir 1.20 / OTP 28, **Phoenix 1.8 + LiveView**.
- **PostgreSQL 18 with Row-Level Security** — per-community isolation. Treat RLS as a hard boundary, not an optimization.
- Oban (jobs), Bandit (server), bcrypt, nanoid.
- Nix flake + direnv for the dev env (`flake.nix`, `.envrc`); `docker-compose.yml` for Postgres.

## Commands (run here, in the app dir)

- `mix setup` — deps + `ecto.create` + `ecto.migrate` + seeds.
- `mix test` — auto-creates/migrates the test DB first.
- `mix test test/path_test.exs` / `mix test --failed` — focused runs.
- `mix precommit` — **run when done.** Compiles `--warning-as-errors`, `deps.unlock --unused`, `format`, `test`. Fix everything it reports.
- `mix ecto.reset` — drop + recreate when migrations get messy.
- Quality tooling present: Credo, Dialyxir (PLTs in `priv/plts`), Styler.

## Conventions

- Phoenix/Ecto/Elixir specifics live in `AGENTS.md` — follow it. Notably: **`Req` is the HTTP client here** (Phoenix default), not Finch — this repo overrides my usual global preference.
- **UI/frontend work**: follow the **Frontend / UI** section of `AGENTS.md` (tokens-only/Penpot as source of truth, Functional Core / Imperative Shell on LiveViews *and* JS hooks, `core_components` reuse, communitarian build directives). Run the `community-ux-reviewer` agent for non-trivial UI.
- Otherwise my user-level conventions apply: Functional Core / Imperative Shell, `@behaviour` over `use` macros, `{:ok,_}`/`{:error,_}` tuples, minimal deps, pattern matching over validators.
- One module per file. Predicate functions end in `?` (never `is_` prefix outside guards).
