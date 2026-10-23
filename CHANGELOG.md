# Changelog

## [0.5.1](https://github.com/taina-labs/taina/compare/v0.5.0...v0.5.1) (2026-10-23)


### Miscellaneous Chores

* update taina sha256 nix module ([a8d187f](https://github.com/taina-labs/taina/commit/a8d187f48593c735da3c5f54d7a50067f6e21492))

## [0.5.0](https://github.com/taina-labs/taina/compare/v0.4.0...v0.5.0) (2026-10-22)


### Features

* close the 0.1.0 review on identity, vault, photos and api ([#174](https://github.com/taina-labs/taina/issues/174)) ([388a341](https://github.com/taina-labs/taina/commit/388a341fe7a0704376f6b1dbb267589d9739f2d8))

## [0.4.0](https://github.com/taina-labs/taina/compare/v0.3.0...v0.4.0) (2026-10-16)


### Features

* **api:** accept an invite and reset a password from the app ([d6bfe62](https://github.com/taina-labs/taina/commit/d6bfe62ed3c0b1360d5c9c0f19bf57540354084d))

## [0.3.0](https://github.com/taina-labs/taina/compare/v0.2.1...v0.3.0) (2026-10-15)


### Features

* **web:** add light theme and refresh home, files and account ([84ca61a](https://github.com/taina-labs/taina/commit/84ca61a8ed9eb75cc5ff0ede5f9d1f052a0dceca))

## [0.2.1](https://github.com/taina-labs/taina/compare/v0.2.0...v0.2.1) (2026-10-14)


### Bug Fixes

* **api:** accept any content type and answer the thumbnail envelope ([#170](https://github.com/taina-labs/taina/issues/170)) ([d718057](https://github.com/taina-labs/taina/commit/d7180576c5627db5ad622ccdc7f252d7f1100be0))

## [0.2.0](https://github.com/taina-labs/taina/compare/v0.1.0...v0.2.0) (2026-10-14)


### Features

* **api:** add the json api v1 and the device token ([#169](https://github.com/taina-labs/taina/issues/169)) ([3ce1615](https://github.com/taina-labs/taina/commit/3ce1615ae21a704768b35a47f07937b55e9d2ba4))


### Bug Fixes

* live health with running version ([889f680](https://github.com/taina-labs/taina/commit/889f680a2683d0795f8c6572b93d01c9ce855b0b))


### Build System

* **nix:** move the NixOS module to oka ([#167](https://github.com/taina-labs/taina/issues/167)) ([e5b1215](https://github.com/taina-labs/taina/commit/e5b121506376ad99fca2e7d5e31fcf66a27cecaf))

## 0.1.0 (2026-10-13)


### Features

* **cli:** add the release verb dispatcher ([#166](https://github.com/taina-labs/taina/issues/166)) ([8edd941](https://github.com/taina-labs/taina/commit/8edd941dcf0d1a10c761bd4dc05e16c315784967))
* complete fase 0 foundation (RFC 002) ([88b7df6](https://github.com/taina-labs/taina/commit/88b7df64ce202fbe65e55f45b38bc325d0e8163e))
* **infra:** connect as a non-superuser role and harden the release image ([8dcc81d](https://github.com/taina-labs/taina/commit/8dcc81d70a04256adc30c741a5bde1705d202f11))
* **infra:** nix flake package and NixOS module ([#162](https://github.com/taina-labs/taina/issues/162)) ([be860a3](https://github.com/taina-labs/taina/commit/be860a3ab57e96d2d03d31c3e73cfe68145e2a59))
* **jaci:** Jaci-lite photo gallery backend (Fase 3) ([#157](https://github.com/taina-labs/taina/issues/157)) ([3a7a753](https://github.com/taina-labs/taina/commit/3a7a753ab3349ba821d3a002d66d371eb35dbdc3))
* maraca member mgmt, login rate limit, session rotation, and nhaman backup ([#160](https://github.com/taina-labs/taina/issues/160)) ([5fb89d3](https://github.com/taina-labs/taina/commit/5fb89d34e483404b359034e91685d596d427d6e5))
* **maraca:** align auth/authz with RFC_003 (D4 access requests, drop :share, doc fixes) ([9a32316](https://github.com/taina-labs/taina/commit/9a3231669d80d9ebc1f4e5dcca46fdd7c2727f03))
* **maraca:** append-only mural ledger with read-only screen ([1701355](https://github.com/taina-labs/taina/commit/1701355272a52dc592a54ca5e0ab21cc4a7c7ec7))
* **maraca:** expose token status, grants and recent decisions for the UI ([0799580](https://github.com/taina-labs/taina/commit/0799580f45f499e827afbb3ffe4da90a72555897))
* **maraca:** implement auth and authorization context ([2adca7a](https://github.com/taina-labs/taina/commit/2adca7ae32757613849ca3f8dcbee59de300a610))
* **maraca:** record every caretaker act on the mural ([9f5e76b](https://github.com/taina-labs/taina/commit/9f5e76bc06f0ddff89ba7672b7659239f289b2cc))
* **nhaman:** opt-in update check and community health screen ([f4f2f61](https://github.com/taina-labs/taina/commit/f4f2f617990bbc04807794c082e5b662d295f714))
* **persistence:** adopt the Ypy kernel and SQLite (RFC 006 step 12) ([#165](https://github.com/taina-labs/taina/issues/165)) ([56824e4](https://github.com/taina-labs/taina/commit/56824e4f6f77fe6e2061e12a7b252af0a1329570))
* schemas Maraca revisitados e extendidos ([#149](https://github.com/taina-labs/taina/issues/149)) ([e50afd6](https://github.com/taina-labs/taina/commit/e50afd6866547fa2fcf4bf8d6b9c99b3404a1f5e))
* schemas mvp respeitanto rfc ([#1](https://github.com/taina-labs/taina/issues/1)) ([d9b5f75](https://github.com/taina-labs/taina/commit/d9b5f759c0f6a1804ff6d72073d69be2ae138970))
* **web:** add iOS launch images so the installed app opens dark ([cb8ef8e](https://github.com/taina-labs/taina/commit/cb8ef8eb68617fcbcde4c137b6277f0aba320cd3))
* **web:** casa/praca files UI + request-access screens (RFC_003 D1/D2/D4) ([45e9f56](https://github.com/taina-labs/taina/commit/45e9f56ca24e816173c162d0db0d01f3c2d61766))
* **web:** desktop file details panel, gallery rail, keyboard shortcuts ([b25af78](https://github.com/taina-labs/taina/commit/b25af783a4d65affc8a187d3b2ce65b474f07319))
* **web:** full folder breadcrumb and context-aware preview back ([81de2a8](https://github.com/taina-labs/taina/commit/81de2a892e0277b6cfcb9e1f7ae2185b98d1eb89))
* **web:** guard expired invite/reset links and add password reveal ([4f869a9](https://github.com/taina-labs/taina/commit/4f869a958658c8f63ba8e0d770fac711181c000e))
* **web:** LiveView frontend (design system + Maraca/Ybira/Jaci screens) ([#159](https://github.com/taina-labs/taina/issues/159)) ([5fde6e9](https://github.com/taina-labs/taina/commit/5fde6e9ad7c84da4c8a3623b1af1f8a442357379))
* **web:** session-to-scope auth glue (plug + LiveView on_mount) ([#158](https://github.com/taina-labs/taina/issues/158)) ([f388325](https://github.com/taina-labs/taina/commit/f3883254289c9afe17b3eddcc2e2be02239a5f65))
* **web:** show granted access and decided requests in the access screens ([f145ba5](https://github.com/taina-labs/taina/commit/f145ba547d6d433107a4d17cc0b4082be3df5b5c))
* **web:** zelador technical dashboard with local telemetry ([e25d0bd](https://github.com/taina-labs/taina/commit/e25d0bd83554672340be087c354e4597733fb92b))
* **ybira:** api publica inicial ([9e3cee1](https://github.com/taina-labs/taina/commit/9e3cee1f749218108b8d62eb7b2b5126a6d3265e))
* **ybira:** fase 2 — pastas, lixeira, paginação, download e cota ([#151](https://github.com/taina-labs/taina/issues/151)) ([88e0446](https://github.com/taina-labs/taina/commit/88e0446096947274fa16856dff85a5868a73d8ab))
* **ybira:** scope aggregates to the read rule and add thumbnail regeneration ([ffc0b7d](https://github.com/taina-labs/taina/commit/ffc0b7de32e27cf58cd5c197026a008bd202787b))
* **ybira:** zonas casa/praça + read rule on every path (RFC_003 D1/D2) ([c7273bd](https://github.com/taina-labs/taina/commit/c7273bd49c686f0ee98d73aced5c5030fc3aa777))


### Bug Fixes

* **ci:** inline the app role password, psql -c does not interpolate ([#163](https://github.com/taina-labs/taina/issues/163)) ([7880378](https://github.com/taina-labs/taina/commit/78803781ed86e8de7183bd6d2be04067ead9e670))
* close five open issues across maraca and ybira ([#164](https://github.com/taina-labs/taina/issues/164)) ([847d2c4](https://github.com/taina-labs/taina/commit/847d2c4ec3be71164ffffbc2950061bb16d37d85))
* **docker:** create the backups dir, rotate container logs ([710604d](https://github.com/taina-labs/taina/commit/710604db53a9ad850f3572f2f04ceb4076ffc486))
* **docker:** drop the unused Node.js install from the image build ([97d11a0](https://github.com/taina-labs/taina/commit/97d11a009fd5c8be0422e4a9fe02827d3eaa48e7))
* **maraca:** revoke pending invites instead of deactivating them ([c8fafda](https://github.com/taina-labs/taina/commit/c8fafdae97a1aef19e39e5f11898c1a3972b7cd1))
* **release:** start postgrex before bootstrap_db ([9193e24](https://github.com/taina-labs/taina/commit/9193e248799502f9e47d2fdce312229b1dc2ef7a))
* **ui:** apply the design review across the app ([714547c](https://github.com/taina-labs/taina/commit/714547cdead9a15d410c561e8ec0aaad1af25b44))
* **web:** correct folder breadcrumb order and preview back target ([db70ceb](https://github.com/taina-labs/taina/commit/db70ceb90a736ebb5282fb44740508ee80fc0440))
* **web:** correct setup validation, recovery copy and onboarding inputs ([5c87563](https://github.com/taina-labs/taina/commit/5c875635ed69889c6a3de7e94cc772b5f4d6744a))
* **web:** dismiss error flashes and re-arm the flash timer ([cbd6a9f](https://github.com/taina-labs/taina/commit/cbd6a9f53ff201843a2f54277b7ad578ab3053b4))
* **web:** handle copy-failed on every clipboard screen ([d015862](https://github.com/taina-labs/taina/commit/d0158628931de18fa429bdb8eb9e774939b96ed9))
* **web:** harden clipboard/share, safe-area, a11y and PWA shell ([da9b6e1](https://github.com/taina-labs/taina/commit/da9b6e1242bd3564f1906886a0c747e4405765a7))
* **web:** honor casa on every read path and tighten copy ([02170a5](https://github.com/taina-labs/taina/commit/02170a52131463310c45bd10bb0e5aef2cba4804))
* **web:** light the account tab on mobile for the members screen ([5539eff](https://github.com/taina-labs/taina/commit/5539eff56efb09d71d3809fdfe9e74774b4994e8))
* **web:** regenerate gettext and close UI review follow-ups ([ca88fd3](https://github.com/taina-labs/taina/commit/ca88fd3afb709ab4e3d605d7dea90cbb7695a4a1))
* **web:** render input without field or value ([14576f0](https://github.com/taina-labs/taina/commit/14576f00c8b1a395ec8fead7da5c49dfa639618f))
* **web:** repair gallery share, vault flow and small-screen actions ([490add9](https://github.com/taina-labs/taina/commit/490add9433a02f2d3b0df35995ffcc9ccb7d8833))
* **web:** serve fingerprinted manifest and icons to PWAs ([c1d7145](https://github.com/taina-labs/taina/commit/c1d71454f1b81899e1921ceefb76b2a60083635d))
* **web:** stop OS file drops from navigating away from the vault ([3e28ee7](https://github.com/taina-labs/taina/commit/3e28ee7d71461f3af6b093a87d8c9f3745451505))
* **web:** tighten governance screens, copy and mobile nav ([6e646ed](https://github.com/taina-labs/taina/commit/6e646edbc3632fba4495a621cccda5c6b6468d19))
* **ybira:** stop the EXIF walk from enumerating a NaiveDateTime ([e97abd7](https://github.com/taina-labs/taina/commit/e97abd7216638c80ef37e721433d0dd587e34736))


### Documentation

* aponta o guia de instalacao e o roadmap no README ([aa1f624](https://github.com/taina-labs/taina/commit/aa1f624b2adc20300a696c7287c3e4d37bc3c2e1))
* politica de seguranca e template de bug ([4da8b00](https://github.com/taina-labs/taina/commit/4da8b006233bd5d0fa94437769ceb298a93baf21))


### Miscellaneous Chores

* add gh sponsorship ([f49eb60](https://github.com/taina-labs/taina/commit/f49eb60afad5e3f6fe48d3b9bcf4a930f97663f0))
* add services contexts readmes ([2fc32a3](https://github.com/taina-labs/taina/commit/2fc32a364637cf162fb238a5ed45c0255beea10f))
* adiciona templates de issues ([fed912a](https://github.com/taina-labs/taina/commit/fed912a5519876eb8d18a2e6aaf624616e390517))
* fix DateTime deprecations and prune unused deps from mix.lock ([4d615e4](https://github.com/taina-labs/taina/commit/4d615e4511db275ccef0f69a7488eeb768aefb25))


### Code Refactoring

* **web:** keep list rows semantically valid where a list mixes content ([bc75f28](https://github.com/taina-labs/taina/commit/bc75f288aa196db2021f688b6c307e803d033e69))
* **web:** render list rows as li and reset ul list styles ([3274deb](https://github.com/taina-labs/taina/commit/3274deb6982cf31bfe9cba526c7bf9593234d1e3))
* **web:** wrap list rows in ul on files, trash, upload and members ([b511b4b](https://github.com/taina-labs/taina/commit/b511b4b540cf7e6b32ffdb6b6fd0b504235c8110))
* **web:** wrap list rows in ul on home, requests, storage and account ([18ab8ac](https://github.com/taina-labs/taina/commit/18ab8ac4747b937cca9e8792172f2d2978676034))


### Tests

* capture log and IO so mix test stays quiet ([568a64d](https://github.com/taina-labs/taina/commit/568a64d280ed8f2a4e2f8d12a4de4688dc281cee))


### Build System

* set the first release to 0.1.0 ([d5b2f89](https://github.com/taina-labs/taina/commit/d5b2f891380dfebe6d531650b7f3182909e4d7f7))


### Continuous Integration

* build the image from the release tag, not the branch tip ([7256367](https://github.com/taina-labs/taina/commit/7256367f5d5fdf56c5e3259e0c972bb562c0e8cf))
* config ([9ec87b4](https://github.com/taina-labs/taina/commit/9ec87b428469aee6ebf026ad29b8db42b1ac6bc5))
* fix elixir version ([4155dae](https://github.com/taina-labs/taina/commit/4155dae3d0179f9f903f1b1de84981690d9692b1))
* smoke test que sobe a imagem de producao de verdade ([1e31da3](https://github.com/taina-labs/taina/commit/1e31da3133956dacc87da7169831ad98627b0a0d))
