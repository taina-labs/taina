# Changelog

## [0.8.0](https://github.com/taina-labs/taina/compare/v0.7.1...v0.8.0) (2026-11-11)


### Features

* **files:** add multi-select actions ([d5e73fb](https://github.com/taina-labs/taina/commit/d5e73fbeb86b50670af59e1a8afaf7b282c6d088))
* **files:** show move destinations as a tree ([4b2fcdf](https://github.com/taina-labs/taina/commit/4b2fcdfa6d297a765d93f8e403ef64e21056bcf2))
* **files:** show move destinations as a tree ([90341de](https://github.com/taina-labs/taina/commit/90341deb7612b974b82fcf3dccf0307e12f83ccb))
* **okena:** import Flutter app ([8a6d2b9](https://github.com/taina-labs/taina/commit/8a6d2b9065e6a37ea5c010e1dea791e70ea65cc4))
* **site:** import public website ([93fddaf](https://github.com/taina-labs/taina/commit/93fddaf83b9cf1855a6cbdd5bf7e021456387023))
* **trash:** add explicit permanent deletion ([5e695f4](https://github.com/taina-labs/taina/commit/5e695f4df59340a641a3937bd6f7ed373d116311))


### Bug Fixes

* **access:** handle revoked grants without crashing ([cc87018](https://github.com/taina-labs/taina/commit/cc87018b56a54828bd2ce14d1a40ac0726a0dab1))
* **account:** handle reset lookup and persistence failures ([8b38ee7](https://github.com/taina-labs/taina/commit/8b38ee792c663607ef98ab8c3e7f0afbb7dbc4c3))
* **backup:** require secrets when packaging ([0f43e32](https://github.com/taina-labs/taina/commit/0f43e3221daa4806bdbf2b4d2747f586dd52dac6))
* **blobs:** make disk writes atomic ([463fd4a](https://github.com/taina-labs/taina/commit/463fd4a6ac595cd6aa70f7b8b8039b57001c6d21))
* **config:** restrict WebSocket origins ([67e41b7](https://github.com/taina-labs/taina/commit/67e41b7199510dbb8f983984bf85d5f22fae93d5))
* **files:** serve SVG as attachments ([437e325](https://github.com/taina-labs/taina/commit/437e325eabd12de3bb561722c9a0fd341e9b435b))
* **health:** ignore unrelated PubSub messages ([cfb4abc](https://github.com/taina-labs/taina/commit/cfb4abc1c4dfc8cc2a7eabdf9eb5158129066cd0))
* **home:** use community clock for greetings ([5a74d03](https://github.com/taina-labs/taina/commit/5a74d030bc08c2f8b6dc2bd6b519ab127a45d1bf))
* **invites:** unify application deep links ([17dee9e](https://github.com/taina-labs/taina/commit/17dee9ed52c5974dba61f76e3efb0a9c58b8c29e))
* **keys:** separate initialization from rotation ([297d249](https://github.com/taina-labs/taina/commit/297d249cf29cf147a317293d053768b2efc1de28))
* **layouts:** centralize browser theme color ([f4e4336](https://github.com/taina-labs/taina/commit/f4e4336a8700e9a4a6665adb7ec52a7a7bdb9c50))
* **lexicon:** reject non-string union types ([663e1ab](https://github.com/taina-labs/taina/commit/663e1ab3886d17f083d684a17bbfa665ceb64e1b))
* **maraca:** protect last zelador in transaction ([163b6fe](https://github.com/taina-labs/taina/commit/163b6fe664debce6e914522e6b9129ac18782f24))
* **mural:** describe unlimited quota correctly ([ba55b9f](https://github.com/taina-labs/taina/commit/ba55b9fff54f45f354fbae53fc64060f6820e86f))
* **mural:** verify chains across key rotations ([524b6d0](https://github.com/taina-labs/taina/commit/524b6d0875a712bf3f61e6dde3a274d391401a84))
* **okena:** resolve monorepo contract links ([cd29e4a](https://github.com/taina-labs/taina/commit/cd29e4a2538237c37167ace5a733e89184f38fea))
* **preview:** normalize text encoding ([6219fcb](https://github.com/taina-labs/taina/commit/6219fcb2b35bb2d46acbe5aa00ce2d6bebc99d78))
* **storage:** keep progress values in percent ([a3efbfa](https://github.com/taina-labs/taina/commit/a3efbfaf47faaef426e1ae701f3df6159d76eddd))
* **thumbnails:** reject unknown tekoa ids ([a615464](https://github.com/taina-labs/taina/commit/a615464fc09652fa60e872e65532eda7d150a16b))
* **trash:** remove photo renditions on purge ([f7df19a](https://github.com/taina-labs/taina/commit/f7df19a06fa50f261d1f5f3d3c6902276f333fc7))
* **update:** contain HTTP client failures ([c20c11c](https://github.com/taina-labs/taina/commit/c20c11cdb71d414d5c25bac1750484b95475609e))
* **uploads:** read multipart limits at runtime ([532c152](https://github.com/taina-labs/taina/commit/532c152de37c97d210d98a27cf49a886dbb7695b))
* **ybira:** enforce read access and preserve blobs ([b4d2dde](https://github.com/taina-labs/taina/commit/b4d2dde5e7a86709ae92d7b283aae4cf5eb156d5))


### Documentation

* add privacidade lgpd disclaimer ([7fa7ed2](https://github.com/taina-labs/taina/commit/7fa7ed2109cb62b2c813449eaa43eb1420387c73))
* align repository guidance with the 1.0.0 scope ([360fa31](https://github.com/taina-labs/taina/commit/360fa316468b366313fd653240c2fc2ae080640e))
* **maraca:** correct storage and policy claims ([69f378c](https://github.com/taina-labs/taina/commit/69f378c30ff3d736e446af68973bf391b578ff72))
* **ybira:** remove unsupported feature claims ([fc242af](https://github.com/taina-labs/taina/commit/fc242af1612318ca591de8ea466b0918a92f0416))


### Miscellaneous Chores

* add coderabbit file ([1682c5f](https://github.com/taina-labs/taina/commit/1682c5f26f7823e23597132a42add641a164747f))
* coderabbit logo ([7e6d92a](https://github.com/taina-labs/taina/commit/7e6d92acfaebe88c9c59706ce0c286c1476368cd))
* **credo:** configure expanded checks ([76d31cd](https://github.com/taina-labs/taina/commit/76d31cd0e15488757bc8dd9073e2b247ecddcabd))


### Code Refactoring

* **backup:** simplify secret validation ([732269f](https://github.com/taina-labs/taina/commit/732269f09b255964a9c16238e7d2ce2d6b59da51))
* bound collection length checks ([03bb97f](https://github.com/taina-labs/taina/commit/03bb97f1ce6130b2dc803a42ec709b0775008372))
* **nix:** share OCI container runtime ([83243b9](https://github.com/taina-labs/taina/commit/83243b94d6088d40ed54fc545c0a455d794f5b0a))
* **taina:** apply expanded credo cleanup ([97a75d8](https://github.com/taina-labs/taina/commit/97a75d88df7bd5c9206aa17ce03003103398e8cf))
* **thumbnails:** simplify tekoa lookup ([1d66806](https://github.com/taina-labs/taina/commit/1d66806f792009d254ac0a0721eb1760f1eae64c))
* **trash:** flatten selection filtering ([c995d4e](https://github.com/taina-labs/taina/commit/c995d4e244b4add7cfdd78cb7c9a14493920aa9e))
* **web:** apply expanded credo cleanup ([6a833a2](https://github.com/taina-labs/taina/commit/6a833a274a8ea9f3c54be6cc41a31095bdf11739))
* **ypy:** apply expanded credo cleanup ([81224f7](https://github.com/taina-labs/taina/commit/81224f77dff019da3e85c45f2919ffdd6b9989ee))


### Tests

* **ybira:** alias blocking blob store ([3bdc863](https://github.com/taina-labs/taina/commit/3bdc86332f47c01c16a3b728f819c5e750cc7eea))


### Continuous Integration

* prepare independent monorepo releases ([fe99c8b](https://github.com/taina-labs/taina/commit/fe99c8bf4a1f5373ccfc0c4d88a9012976fdf2c3))

## [0.7.1](https://github.com/taina-labs/taina/compare/v0.7.0...v0.7.1) (2026-11-03)


### Bug Fixes

* **files:** hide root breadcrumb ([58403e3](https://github.com/taina-labs/taina/commit/58403e3f53e6bafb4c35fa87b38712bc2c9fb900))
* **trash:** use actions menu in preview ([504ffc0](https://github.com/taina-labs/taina/commit/504ffc0556f343b302a93e0251e86ebc3e4ad0bc))

## [0.7.0](https://github.com/taina-labs/taina/compare/v0.6.1...v0.7.0) (2026-11-03)


### Features

* add release operator API and OCI deployment ([c067ef4](https://github.com/taina-labs/taina/commit/c067ef417888e03eae1b0fc52740f59eab7e6ce0))
* **config:** expose upload limits ([ec019d1](https://github.com/taina-labs/taina/commit/ec019d1b6980e56fe8b5e1a64e6c182e345f32fa))
* **devices:** mark current access ([c712c84](https://github.com/taina-labs/taina/commit/c712c8497282694a6d3291a85ad671d16ac3ecf3))
* **trash:** add owner-only file previews ([5435509](https://github.com/taina-labs/taina/commit/5435509f391505338da5a923e311d99d937941f6))
* **upload:** enforce configured blob size ([08307c2](https://github.com/taina-labs/taina/commit/08307c22089aea3765470741a962e223e3d6f968))


### Bug Fixes

* **preview:** explain unsupported video formats ([f260984](https://github.com/taina-labs/taina/commit/f2609843ff84a871bd257208152df39844c10291))
* **upload:** cap file selection at ten ([a844b46](https://github.com/taina-labs/taina/commit/a844b462b7803f92a7149c69c9e5b22bd65eede1))
* **upload:** clear captured file input ([accf506](https://github.com/taina-labs/taina/commit/accf506dbda77914b8d37db2e435100509e5d66e))
* **upload:** ignore duplicate native change events ([9b7fd35](https://github.com/taina-labs/taina/commit/9b7fd35ef06c6cc7fcab9de0956c3216b5415676))
* **upload:** queue concurrent file batches ([013359a](https://github.com/taina-labs/taina/commit/013359a7d16241c3c347736020b3197952a40296))
* **upload:** stop paired change propagation ([b491fc9](https://github.com/taina-labs/taina/commit/b491fc969bc387b35e27e05e9dcd0aaebb68b0c2))
* **upload:** wait for refs before next batch ([a76c883](https://github.com/taina-labs/taina/commit/a76c88302328eeeb93a25f9ba1ca46a99389f13f))
* **web:** keep downloads outside live navigation ([5e8af1b](https://github.com/taina-labs/taina/commit/5e8af1b46136eb0fddc333c6041c8f0f2c3823a1))


### Miscellaneous Chores

* **nix:** migrate dev shell to beam-overlay ([79b88a2](https://github.com/taina-labs/taina/commit/79b88a20bc978f7a0d5d47df2c2bfa3315fc5372))


### Code Refactoring

* **upload:** defer background queue ([7042b8a](https://github.com/taina-labs/taina/commit/7042b8a383a1d7f5e85e926fa957744510e80c72))

## [0.6.1](https://github.com/taina-labs/taina/compare/v0.6.0...v0.6.1) (2026-11-02)


### Bug Fixes

* nix fod deps hash ([d6da132](https://github.com/taina-labs/taina/commit/d6da132affe75013da043528635c9b1cc38e3719))

## [0.6.0](https://github.com/taina-labs/taina/compare/v0.5.1...v0.6.0) (2026-11-01)


### Features

* **web:** count folder items, gallery totals and owner refusals ([147f229](https://github.com/taina-labs/taina/commit/147f2292721c75ce7d430d5db9af3be32e0bcd0c))
* **web:** refine navigation and community activity flows ([9b909f4](https://github.com/taina-labs/taina/commit/9b909f41bd1709295fb401d5e6826be03f0f5506))


### Bug Fixes

* **a11y:** correct labels contrast and landmarks ([748a082](https://github.com/taina-labs/taina/commit/748a0820f14731af2bf483bad13c83480db41bd1))
* **access:** hide revoked grants from request history ([924cc44](https://github.com/taina-labs/taina/commit/924cc44ee51805c24c2fe97ba1d531246c6cc2e7))
* **account:** distinguish sent and received requests ([e7fb9e1](https://github.com/taina-labs/taina/commit/e7fb9e1496929dbe49daa0f6012a15e02fb99705))
* **account:** remove stale password and quota state ([9272a01](https://github.com/taina-labs/taina/commit/9272a012891d8609f1e29de2f0e02203581d2546))
* **auth:** preserve login and setup form data ([8e78f42](https://github.com/taina-labs/taina/commit/8e78f420215798c971f4e14cb17fb0ca02720c4d))
* **auth:** retain request URI in LiveView ([d662b43](https://github.com/taina-labs/taina/commit/d662b43fac2a8bb3a59a77f77e64b139e4a42e46))
* **files:** keep folder contents visible across zones ([bec20c2](https://github.com/taina-labs/taina/commit/bec20c28dc0091c34ae5dc30bd698ad7433145f1))
* **members:** hide pending invites from residents ([1663487](https://github.com/taina-labs/taina/commit/1663487ef00657795b869728afab754aaf00e0a3))
* **mural:** name access recipients ([482a991](https://github.com/taina-labs/taina/commit/482a991f9c523823ab466c69f4c326c714a8d3bc))
* **navigation:** preserve gallery and file return paths ([6888cf3](https://github.com/taina-labs/taina/commit/6888cf3dbddc6b6df85b0492ed3f4e5ce882ed9f))
* **seeds:** publish community example content ([9ae8598](https://github.com/taina-labs/taina/commit/9ae8598b3c1c24ee76f3d39c9156dbd0233ca950))
* **ui:** align badges and file actions with design ([49103b2](https://github.com/taina-labs/taina/commit/49103b2d697b4b7f09417f77d429939bd40de8c1))
* **ui:** remove inert menu focus trap ([fd30404](https://github.com/taina-labs/taina/commit/fd30404db1e5058e6993ce625bd37659faf0e4b4))
* **web:** add the error card contact action and use the penpot cota copy ([da1df92](https://github.com/taina-labs/taina/commit/da1df923b1bf014a092bb10d2060b36faa1835d9))
* **web:** add the penpot warning icon and use it for warning states ([d961672](https://github.com/taina-labs/taina/commit/d96167296847073e85589bcac82f6c3c7db773e7))
* **web:** align the auth screens with the penpot boards ([89097b0](https://github.com/taina-labs/taina/commit/89097b0985d05b2bc1f756c2c547f902c81d8447))
* **web:** use the board's mostrar word for the password reveal ([a8358d7](https://github.com/taina-labs/taina/commit/a8358d7f5099baf87bccfe6037f49e0e48e60e27))


### Documentation

* **web:** point the shells and the ui prompts at the penpot file ([a468b44](https://github.com/taina-labs/taina/commit/a468b44920de127af4d63110c526a08c2e8e0698))


### Miscellaneous Chores

* **gettext:** extract the copy from the rebuilt screens ([1b31a10](https://github.com/taina-labs/taina/commit/1b31a107e857d02d2b0ff18ac9360215198663a1))
* **gettext:** sync extracted messages ([98e8e65](https://github.com/taina-labs/taina/commit/98e8e65a081d85e6165e9e8131010fa7f46e42af))
* **ui:** remove unused styles and components ([1cfae9a](https://github.com/taina-labs/taina/commit/1cfae9a131458c26a387529fce471693220d6f36))


### Code Refactoring

* **access:** batch names outside LiveView render ([9dd03c5](https://github.com/taina-labs/taina/commit/9dd03c5e73605701972f103523803b86d293dc5b))
* components and css following penpot ([f24ba39](https://github.com/taina-labs/taina/commit/f24ba39e71d849e5ec1dd28d300bbeed3a369bed))
* **core:** simplify batched resource queries ([cfe6eaa](https://github.com/taina-labs/taina/commit/cfe6eaa92ca6beea3c37d58766258f73895b289e))
* fold the Ypy kernel back into the app ([645b0e6](https://github.com/taina-labs/taina/commit/645b0e6e51fed7f7f8cf7bbf0bc97a13ab26c102))
* remove pwa ([6d0b42e](https://github.com/taina-labs/taina/commit/6d0b42ee75207979d5190ac7befddb2f3299d7e1))
* remove redundant tests ([22e7ef8](https://github.com/taina-labs/taina/commit/22e7ef8a4ee2fe8b76961d49b66e6edf396826a0))
* remove req for a single http request ([05bbfc8](https://github.com/taina-labs/taina/commit/05bbfc8171853d43558784957761df1dea51fa9e))
* remove unecessary deps, update others ([217e743](https://github.com/taina-labs/taina/commit/217e743ef88f676e91030c37bc72833fa400aa37))
* **ui:** consolidate shared view helpers ([2c7a976](https://github.com/taina-labs/taina/commit/2c7a9766342ffcf0bbb17c65ee1b1b0814898123))
* **web:** add the hub, service, page, auth and viewer shells ([3cf0845](https://github.com/taina-labs/taina/commit/3cf0845a24776ebef8b4b0c801749bf9ff41fcf6))
* **web:** align content and feedback components with penpot ([875e613](https://github.com/taina-labs/taina/commit/875e613a973a18fd8923d252de0cddfa31e29cd2))
* **web:** align overlays, navigation and media with penpot ([8f80401](https://github.com/taina-labs/taina/commit/8f80401c8576a265e67b3e731cf1d22ba0dbb4fb))
* **web:** align primitive components and icons with penpot ([c9c470b](https://github.com/taina-labs/taina/commit/c9c470b1753d50870c495cc22da4026b374f7afc))
* **web:** delete the deprecated design system wrappers ([7ee9bb5](https://github.com/taina-labs/taina/commit/7ee9bb58b745264d8512361c0f17ca4c1c4b0ee1))
* **web:** move every screen onto the new shells and drop the old one ([b190516](https://github.com/taina-labs/taina/commit/b19051662937e15bd1e287567130695f7f1643dc))
* **web:** rebuild documentos from the penpot boards ([6126ec7](https://github.com/taina-labs/taina/commit/6126ec79a1d90e97ba7e419f5e7866a5c660a93a))
* **web:** rebuild moradores, conta and pedidos from the boards ([43ebf9f](https://github.com/taina-labs/taina/commit/43ebf9f55a89553bf4176ea1a358ba4d46b4dc39))
* **web:** rebuild mural, saude and armazenamento from the boards ([95c318b](https://github.com/taina-labs/taina/commit/95c318b0b07870adb940318d5a81e2e0f53d35d0))
* **web:** rebuild the auth screens from the penpot boards ([6c0c49f](https://github.com/taina-labs/taina/commit/6c0c49fdd4802f1bd7f5d01cb2e7ba40a9160385))
* **web:** rebuild the galeria and trim the viewer to the board ([1314d1d](https://github.com/taina-labs/taina/commit/1314d1defbf393a8a7eec9c48e554cc12ae9989b))
* **web:** rebuild the hub from the penpot boards ([6e3823d](https://github.com/taina-labs/taina/commit/6e3823d7d97b32636f89973ea448ab3cbe60cea6))
* **web:** remove the light theme ([f9c5b4f](https://github.com/taina-labs/taina/commit/f9c5b4fd84ded0dd4a72cb01bbd90c9d7488c556))
* **web:** rename routes to the ui names and add the privacy and invite stubs ([7180d2e](https://github.com/taina-labs/taina/commit/7180d2ef201edd8889bb95e2816a97baeb6396d4))
* **web:** share saude summary and add storage by zone ([cec79cb](https://github.com/taina-labs/taina/commit/cec79cbd7bc2b45a987b3dbf1e8b7e5bd1de77a0))
* **ypy:** simplify the kernel and fix resource access ([454114c](https://github.com/taina-labs/taina/commit/454114c2369e6b8428bd1bdabb1088799fdfba3d))


### Tests

* **policy:** align member and expiry expectations ([b208f88](https://github.com/taina-labs/taina/commit/b208f88a0d0f45e5b451761541556ea158a054e4))

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
