This is a web application written using the Phoenix web framework.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->

## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you _must_ bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->

## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:ecto-start -->

## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text`, columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such as option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct
<!-- phoenix:ecto-end -->

<!-- usage-rules-end -->

## Frontend / UI

Rules for building Tainá's web UI (LiveViews, components, CSS, JS hooks). These
are non-negotiable; when in doubt, read the cited examples in the repo.

### Source of truth

- The aesthetic is **already committed** in Penpot ("Cofre da Comunidade - UI
  v1") and mirrored 1:1 in `assets/css/tokens.css`. **Do not invent a look.**
  You are executing a design, not freestyling one — precision over novelty.
- `tekoa/` docs win over instinct. For non-trivial UI, run the
  `community-ux-reviewer` agent before shipping; it grounds on the docs and
  argues the product, not just the pixels.

### Tokens — never raw values

- Two levels: **primitives** (raw palette/scale) → **semantic** (what
  components consume). Components consume **semantic only** — never a primitive,
  never a raw hex or px in `.heex` or component CSS.
- A new value is born as a **semantic token first** (and must trace back to
  Penpot). No magic numbers in markup.
- Typography: use the `type-*` utility classes and the type scale. Fonts are
  fixed — Bricolage Grotesque (display) / Schibsted Grotesk (body) / JetBrains
  Mono (mono). **Don't add fonts.**
- Color: dark-first night palette via semantic tokens (`--text-*`,
  `--surface-*`, `--border-*`, `--brand-*`). Each subsystem has a service accent
  (`--service-ybira` forest, `--service-jaci` moon, …) — use it, don't recolor.
- No AI slop: no Inter/Roboto/Arial/system fonts, no purple-on-white, no
  cookie-cutter layouts. The character is the dark Tupi-Guarani vault — keep it.

### Functional Core / Imperative Shell (LiveView **and** JS)

This is the single most important rule and it applies to the frontend too.

- **LiveView callbacks are the imperative shell.** `mount`, `handle_params`,
  `handle_event` stay thin — they only `assign` / `stream` / `push_patch` /
  `put_flash`. Every decision lives in **pure private helpers that take data and
  return data**, not the socket. See `gallery_live.ex`: `merge_groups/2`,
  `step/2`, `group_title/1`, `viewer_index/2`, `video?/1` — logic out of the
  callbacks, callbacks just wire results in.
- **Domain logic lives in contexts** (Maracá / Ybira / Jaci). The LiveView
  *calls* the context and shapes the result for the view; it never reimplements
  business rules. Always pass through `current_scope` (RLS boundary).
- `assign_new/3` for derived/cached state that must survive the HTTP → WebSocket
  handoff (see `hooks.ex` `storage_stats` — computed once, not re-queried).
- **JS hooks are the edge, kept minimal.** Before writing a hook, check a native
  binding (`phx-viewport-*`, `phx-drop-target`, `JS.*`) already solves it
  (`hooks.js` opens with exactly this reminder). A hook only touches DOM events
  and browser APIs (clipboard, share, keyboard/swipe); it `pushEvent`s and lets
  the **server decide and own state** (see `Clipboard`, `ViewerNav`). Keep pure
  transforms separate from DOM mutation. Functional Core / Imperative Shell —
  including in JS.

### Components & layout

- **Reuse `core_components`** (`.button`, `.modal`, `.confirm_dialog`,
  `.empty_state`, `.segmented`, `.icon`, `.icon_button`). Don't hand-roll a
  primitive that already exists.
- CSS: **BEM** for component classes (`block__element--modifier`, e.g.
  `photo-grid__item`); **utility classes** for layout/spacing (`row between`,
  `col gap-5`, `center`, `mt-4`, `type-*`). One LiveView per screen; wrap in
  `Layouts.app`.
- **Every screen ships empty / error / permission states** — not just the happy
  path. `<.empty_state>` exists for this; use it.
- All user-facing strings go through `gettext` / `ngettext`. **pt-BR first.**
  Never anglicize the Tupi-Guarani names (Tekoa, Maracá, Ybira, Jaci, Guará).

### Motion & accessibility

- Motion is **CSS-first and restrained** — one high-impact moment beats
  scattered micro-animations. Respect `prefers-reduced-motion`.
- Touch targets ≥ `--size-touch` (44px). Icon buttons need a `label`. Images
  need `alt`. Keyboard + swipe navigation where it matters (the `ViewerNav`
  pattern). Visible focus states.

### Build for the audience (communitarian, non-technical)

These are build directives distilled from `community-ux-reviewer` — apply them
*while building*, not only in review.

- **Design for the least-technical person in the community**, not power users.
  No jargon, no assumed technical knowledge, no dead-ends.
- **Commons, not a personal account.** Favor shared spaces, collective memory,
  and stewardship ("who keeps this organized") over individualist patterns:
  profiles, vanity metrics, likes/followers, algorithmic feeds, and
  attention-bait notifications. Default to shared-by-norm with **explicit,
  legible consent**, not private silos.
- **One community per box** — hard-enforced. No multi-community switching, no
  public discovery, no cross-instance feed. The "network" is this one Tekoa.
- **Onboarding is by invitation** — arriving as belonging, not signing up alone.
- **LiveView / Raspberry Pi feasibility lens on every interaction.** Server-
  rendered, mobile-first, low client state. No offline-PWA assumptions, no heavy
  client-side state machines. Don't fight the architecture.
- **Respect the scope cuts.** MVP = the community's file + photo vault. Chat
  (Guará) is out of MVP — never propose chat as the way to be "more
  communitarian"; find that value in files / photos / people / governance.

### Plain text: no AI-typography, no emoji

Text Tainá ships or that people read as docs reads like a human wrote it: UI
copy / gettext, docs (including the `tekoa` repo), production comments and
moduledocs under `lib/`, and commit/PR prose. No AI-typography tells, no emoji.
Use plain ASCII:

- `—` / `–`: comma for an aside, colon for a definition (`**Label**:`, headings,
  titles), or a period to split a sentence. Choose by context.
- `·` / `•`: comma in metadata (`PDF, 2,4 MB`), or ` / ` when a comma clashes.
- `…` to `...`; curly quotes `" " ' '` to straight `" '`; `×` to `x`; `→` to
  `->` or a word ("para", "depois").
- Emoji: remove. Do/don't markers become text (`✅` / `❌` to `Bom:` / `Evite:`).
- Keep intentional ASCII-art diagrams (box-drawing `─ │ └ ├` and their arrows):
  deliberate, not typography.

Humanize the sentence, don't just swap the glyph; align to the docs voice and
`community-ux-reviewer`. `test/**` comments are out of scope (the `→` / `—`
shorthand there is useful and stays); only fix a test when an assertion must
match changed UI copy. Verify with a unicode grep after editing. Note: `rtk`
rewrites a *leading* `grep`/`find`, which silently breaks unicode scans, so run
`find … -print0 | xargs -0 grep -P '…'` or `perl -CSD -i -pe`.

### Social model & transparency (Tainá-specific, non-negotiable)

Decided 2026-06-15 (canonical record: `tekoa/tecnico/RFC_003_GOVERNANCA_E_TRANSPARENCIA.md`).

- **Two zones, not one pile.** Content lives in **praça** (commons —
  shared-by-norm, every morador reads; placing a file there IS the reversible
  consent) or **casa** (personal — private-by-default; only the owner reads,
  and *everyone else, including the zelador,* must `request_access` → owner
  approves). New files default to **casa**. Read paths in Ybira/Jaci enforce
  this (`zone == :praca OR Maraca.authorize?`), never tekoa-wide.
- **Zelador, not admin.** Reframe the role as **zelador(a)** — caretaker of the
  machine (disk, backups, updates, invites) with **zero data authority and zero
  unilateral social power**. `member`→**morador(a)**. A tekoa may have
  **multiple zeladores**. Tainá is pre-alpha → **rename the enum cleanly** in a
  migration (`admin`→`:zelador`, `member`→`:morador`) — no cookie-session
  caution needed. Predicates `Maraca.zelador?/1`/`morador?/1`. The zelador has
  **no read shortcut** to a morador's casa — confirm this stays true.
- **Transparency is a core pillar, not a feature.** Three layers, all MVP:
  the **Mural** (append-only social ledger — who did what), the **Painel /
  "Saúde da comunidade"** (system state in plain pt-BR), and the **telemetry +
  structured-logging substrate** (`:telemetry`, `telemetry_metrics`, `Logger`
  metadata). **SOVEREIGN — never phone home.** Telemetry/metrics/logs stay on
  the community's box; shipping community data to any SaaS (PostHog, etc.)
  betrays data sovereignty. Accessibility (WCAG contrast/labels/focus) is *part
  of* accessible transparency, not separate polish.
- **Honest framing.** No encryption exists yet. UI must say casa privacy is a
  *software + trust* promise ("promessa de software, não cadeado matemático"),
  never a cryptographic guarantee. Only future Ybira **E2E** (not convergent)
  would let us honestly say the zelador *cannot* read casa files.
- **Governance is collective.** Sensitive acts (remove member, appoint/revoke
  zelador) are community-voted *proposals* (assembleia), never a god-button —
  but that track is beyond RFC_002 and ships only after its tekoa RFC lands.
- **Naming is tiered — one source of truth.** **Tupi-Guarani** for
  subsystem/brand proper nouns only (Tekoa, Maracá, Ybira, Jaci, Guará).
  **Familiar pt-BR** for the everyday social vocabulary, where the *same word*
  is the DB atom, the context term, **and** the UI label — `:casa`, `:praca`,
  `:zelador`, `:morador`, mural, pedido, assembleia — no English-atom →
  pt-BR-label translation seam. **English** only for invisible plumbing users
  never read (Repo, Scope, Telemetry). This is the deliberate exception to
  "code in English" — same justification as the intentional Tupi naming, and it
  serves the non-technical pt-BR audience.

### Penpot is the UI source of truth — verify, then build

- The Penpot design system is **complete and code-implemented** (foundations,
  components, tokens, mobile + desktop); `assets/css/tokens.css` is imported
  directly from Penpot. **Do not re-import tokens or invent foundations** —
  compose new screens from the existing components + tokens.
- The Penpot **MCP is live**. **Before non-trivial UI work, verify the live
  file first** via the `community-ux-reviewer` agent (it holds the
  `mcp__penpot__*` tools; the main loop does not). **Editing Penpot is
  authorized** — refactor/improve boards within the existing token/component set
  when it helps.
