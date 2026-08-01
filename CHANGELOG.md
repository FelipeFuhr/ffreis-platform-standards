# Changelog

## [1.9.0](https://github.com/FelipeFuhr/ffreis-platform-standards/compare/v1.8.0...v1.9.0) (2026-08-01)


### Features

* **lefthook:** add ansible.yml shared config ([#78](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/78)) ([9f60788](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/9f607886fec75e332773f9c0137a9b8e9b6b09da))


### Bug Fixes

* use exit not return in check_required_tools.sh ([#86](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/86)) ([750f106](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/750f106efccce10e1bf95f99695e329bf808cd21))

## [1.8.0](https://github.com/FelipeFuhr/ffreis-platform-standards/compare/v1.7.4...v1.8.0) (2026-07-29)


### Features

* add ci and tooling ([#1](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/1)) ([aa1c9d9](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/aa1c9d9ce5c956a52f027b3ead76601ee67387a8))
* add lefthook bootstrap script and hook scripts ([#9](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/9)) ([1b8d074](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/1b8d074407bae32498110c98fd09f1e41f8fe99e))
* add renovate presets, lefthook remotes, golangci template ([b70c99f](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/b70c99fdf3a180d01c2dbbbd618edaa8e2fcda75))
* **ci-local:** --findings mode — capture act SARIF locally, report + classify ([#48](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/48)) ([053902a](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/053902a46da02d0500f297c06f5ba697f247adc7))
* **ci-local:** self-bootstrap ci-local-findings.py so --findings needs no Makefile change ([#50](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/50)) ([45def9f](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/45def9fbc75fe40ad2ce40a65501b830868f250a))
* **flags:** promote canonical flag-registry schema from heavy-heater ([#76](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/76)) ([db4fe39](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/db4fe3919f55cdabd0e6bd6d5d4ec0ff00ebdea9))
* **hooks:** add lefthook/kotlin.yml and lefthook/swift.yml ([#64](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/64)) ([e651c67](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/e651c6790984167ba5f275037e363597240617e1))
* **hooks:** call pre-commit via lefthook when .pre-commit-config.yaml exists ([#62](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/62)) ([3d98c9a](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/3d98c9aa580e1c43ebebaa0cbceffa63626aba8b))
* **lefthook:** add complex + release heavy-check tiers ([#40](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/40)) ([ca35654](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/ca3565422a40f059da455f1b4f0877e4c7d59412))
* **lefthook:** pre-commit drift gate on workflow changes ([#51](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/51)) ([d030561](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/d030561668dea4370fb8d8cafc80b5fbd763d012))
* platform leveling improvements ([#8](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/8)) ([9ad0451](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/9ad0451bce4b1137c301e53f0745a81fa1ab0281))
* **renovate:** track PLATFORM_STANDARDS_SHA in Makefiles + lefthook.yml ([#29](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/29)) ([eecb45b](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/eecb45b907e5fbcf35625581fb8b350a50000a72))
* **renovate:** track the ffreis-platform-ci-local tag pin ([#53](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/53)) ([3558b6a](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/3558b6a1a5c4982c0e66241ac5a289dbd0a7fb64))
* **scripts:** add act installer and local CI runner ([#14](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/14)) ([d939d38](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/d939d383ea83f95d94df0f0e7b89093da72ba08f))
* **workspace:** parallel-session safety hooks, actionlint/hadolint pre-commit, drift audit ([#31](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/31)) ([4f0aac0](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/4f0aac0ef2a6ff854c8bb8666091ec94e15f9e7c))
* **workspace:** version-track workspace-root AGENTS.md and CLAUDE.md ([#20](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/20)) ([b7503af](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/b7503af83f242f127d0fee970b1844f896fd15f3))


### Bug Fixes

* **ci:** add release-please config and finalize semantic-pr SHA ([#6](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/6)) ([29c2089](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/29c2089f4e291ea9d4240fb6d5df06114ee7cfa1))
* **ci:** fix release-please permissions and remove osv job ([#4](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/4)) ([25bc755](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/25bc755ee8bc686fb853de6281cede2e0a88a160))
* **ci:** fix workflow errors ([#5](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/5)) ([ddb00b2](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/ddb00b20cee1a0b5215818a15b9d234c45db69ad))
* **ci:** install PyYAML before YAML validation step ([aa1c9d9](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/aa1c9d9ce5c956a52f027b3ead76601ee67387a8))
* **ci:** pin ffreis-workflows-general to v1.7.0 ([#70](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/70)) ([700f54d](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/700f54d4c206cb69c729fe5f02e73553505ee778))
* **grype:** bump workflows-general SHA to prevent self-scan CVEs ([#43](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/43)) ([4268f2c](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/4268f2c460dfbb981de16a515509941d9e0cfe62))
* **lefthook:** actionlint-workflows hook errors on staged deletions ([#74](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/74)) ([5ab6640](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/5ab664049219ed3b8e3ac1ed7a9164f109a5e5e4))
* **lefthook:** allow application/javascript and application/ecmascript MIME types ([#72](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/72)) ([17ee8a9](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/17ee8a97a4a2e5ea69025d9eb7e4224589a10a44))
* **lefthook:** drop pipefail from inline run blocks for sh portability ([#13](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/13)) ([6e89ee5](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/6e89ee5d2b4b8dcace865bb8c3e29a867c4b86eb))
* **lefthook:** make hygiene-* blocks POSIX-portable ([#16](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/16)) ([dd3256b](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/dd3256b73ccdc3cc53e46c0bcae3a7b4f5e1e817))
* **lefthook:** make hygiene-* exit 0 on the clean path ([#18](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/18)) ([618855b](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/618855b2fba2f356e76ccd35634828e8a8508150))
* **lefthook:** make secret-scan graceful (make→gitleaks fallback→skip) ([#66](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/66)) ([93cacb8](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/93cacb88f43b4ff22161dca81117b2491c3ee3a5))
* **lefthook:** repoint ci-local-drift fetch at ffreis-org ([#81](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/81)) ([51e525d](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/51e525da7570f1c091957e86bfb1f5f0b4a48830))
* **lefthook:** stop hygiene-binary-files rejecting plainly-textual sources ([#85](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/85)) ([438afd1](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/438afd1a6827e893b600295a66258e46eeb0ee91))
* **run-ci-local:** auto-detect rootless podman socket, clearer extras-file banner ([#22](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/22)) ([4c66097](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/4c660973c65eec09ece111ea1047100786be16bc))

## [1.7.4](https://github.com/ffreis-org/ffreis-platform-standards/compare/v1.7.3...v1.7.4) (2026-07-18)


### Bug Fixes

* **lefthook:** repoint ci-local-drift fetch at ffreis-org ([#81](https://github.com/ffreis-org/ffreis-platform-standards/issues/81)) ([51e525d](https://github.com/ffreis-org/ffreis-platform-standards/commit/51e525da7570f1c091957e86bfb1f5f0b4a48830))

## [1.7.3](https://github.com/FelipeFuhr/ffreis-platform-standards/compare/v1.7.2...v1.7.3) (2026-07-02)


### Bug Fixes

* **lefthook:** actionlint-workflows hook errors on staged deletions ([#74](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/74)) ([5ab6640](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/5ab664049219ed3b8e3ac1ed7a9164f109a5e5e4))

## [1.7.2](https://github.com/FelipeFuhr/ffreis-platform-standards/compare/v1.7.1...v1.7.2) (2026-07-02)


### Bug Fixes

* **lefthook:** allow application/javascript and application/ecmascript MIME types ([#72](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/72)) ([17ee8a9](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/17ee8a97a4a2e5ea69025d9eb7e4224589a10a44))

## [1.7.1](https://github.com/FelipeFuhr/ffreis-platform-standards/compare/v1.7.0...v1.7.1) (2026-06-26)


### Bug Fixes

* **ci:** pin ffreis-workflows-general to v1.7.0 ([#70](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/70)) ([700f54d](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/700f54d4c206cb69c729fe5f02e73553505ee778))

## [1.7.0](https://github.com/FelipeFuhr/ffreis-platform-standards/compare/v1.6.0...v1.7.0) (2026-06-14)


### Features

* **hooks:** add lefthook/kotlin.yml and lefthook/swift.yml ([#64](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/64)) ([e651c67](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/e651c6790984167ba5f275037e363597240617e1))


### Bug Fixes

* **lefthook:** make secret-scan graceful (make→gitleaks fallback→skip) ([#66](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/66)) ([93cacb8](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/93cacb88f43b4ff22161dca81117b2491c3ee3a5))

## [1.6.0](https://github.com/FelipeFuhr/ffreis-platform-standards/compare/v1.5.0...v1.6.0) (2026-06-14)


### Features

* **hooks:** add lefthook/kotlin.yml and lefthook/swift.yml ([#64](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/64)) ([e651c67](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/e651c6790984167ba5f275037e363597240617e1))
* **hooks:** call pre-commit via lefthook when .pre-commit-config.yaml exists ([#62](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/62)) ([3d98c9a](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/3d98c9aa580e1c43ebebaa0cbceffa63626aba8b))

## [1.5.0](https://github.com/FelipeFuhr/ffreis-platform-standards/compare/v1.4.0...v1.5.0) (2026-06-11)


### Features

* **lefthook:** pre-commit drift gate on workflow changes ([#51](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/51)) ([d030561](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/d030561668dea4370fb8d8cafc80b5fbd763d012))
* **renovate:** track the ffreis-platform-ci-local tag pin ([#53](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/53)) ([3558b6a](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/3558b6a1a5c4982c0e66241ac5a289dbd0a7fb64))

## [1.4.0](https://github.com/FelipeFuhr/ffreis-platform-standards/compare/v1.3.1...v1.4.0) (2026-06-09)


### Features

* **ci-local:** --findings mode — capture act SARIF locally, report + classify ([#48](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/48)) ([053902a](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/053902a46da02d0500f297c06f5ba697f247adc7))
* **ci-local:** self-bootstrap ci-local-findings.py so --findings needs no Makefile change ([#50](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/50)) ([45def9f](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/45def9fbc75fe40ad2ce40a65501b830868f250a))

## [1.3.1](https://github.com/FelipeFuhr/ffreis-platform-standards/compare/v1.3.0...v1.3.1) (2026-06-07)


### Bug Fixes

* **grype:** bump workflows-general SHA to prevent self-scan CVEs ([#43](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/43)) ([4268f2c](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/4268f2c460dfbb981de16a515509941d9e0cfe62))

## [1.2.1](https://github.com/FelipeFuhr/ffreis-platform-standards/compare/v1.2.0...v1.2.1) (2026-05-24)


### Bug Fixes

* **run-ci-local:** auto-detect rootless podman socket, clearer extras-file banner ([#22](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/22)) ([9843165](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/9843165685f53fa7aebc8ec31313e04a4fe9fbc9))

## [1.2.0](https://github.com/FelipeFuhr/ffreis-platform-standards/compare/v1.1.2...v1.2.0) (2026-05-24)


### Features

* **workspace:** version-track workspace-root AGENTS.md and CLAUDE.md ([#20](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/20)) ([a16b438](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/a16b438c4bcdeb84f55d753f35e879a1edbf50da))

## [1.1.2](https://github.com/FelipeFuhr/ffreis-platform-standards/compare/v1.1.1...v1.1.2) (2026-05-24)


### Bug Fixes

* **lefthook:** make hygiene-* exit 0 on the clean path ([#18](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/18)) ([aacc4aa](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/aacc4aa188654a67e148883bf427ae8ef7a52d31))

## [1.1.1](https://github.com/FelipeFuhr/ffreis-platform-standards/compare/v1.1.0...v1.1.1) (2026-05-24)


### Bug Fixes

* **lefthook:** make hygiene-* blocks POSIX-portable ([#16](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/16)) ([f1b7171](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/f1b7171715ef25c460cf436d5fb77a6e9523de83))

## [1.1.0](https://github.com/FelipeFuhr/ffreis-platform-standards/compare/v1.0.0...v1.1.0) (2026-05-23)


### Features

* add lefthook bootstrap script and hook scripts ([#9](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/9)) ([13304a2](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/13304a2737e81ea41604b8ea9656c1b0448782bf))
* platform leveling improvements ([#8](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/8)) ([f818663](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/f8186639184060c06b524ec916a8da8ff06f835e))
* **scripts:** add act installer and local CI runner ([#14](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/14)) ([1d2cb70](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/1d2cb70b8228d4aee82bd863ae95dcd689c8781a))


### Bug Fixes

* **lefthook:** drop pipefail from inline run blocks for sh portability ([#13](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/13)) ([0a47d0a](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/0a47d0a3e1e6479fb2eeba31adbdc5cb4529c85e))

## 1.0.0 (2026-05-05)


### Features

* add ci and tooling ([#1](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/1)) ([9fbd862](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/9fbd862e5af0da06f98252a44c5f7e66e2fdd9cc))
* add renovate presets, lefthook remotes, golangci template ([691e203](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/691e203d803e53d1fb678ed03fff2405876cbaee))


### Bug Fixes

* **ci:** add release-please config and finalize semantic-pr SHA ([#6](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/6)) ([eb0ef1e](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/eb0ef1e8ccbf9943110dcc9971e5afcdd8ac9927))
* **ci:** fix release-please permissions and remove osv job ([#4](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/4)) ([b5a7dcf](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/b5a7dcf7a064c88e9b5d22b0f9439c4c5800a155))
* **ci:** fix workflow errors ([#5](https://github.com/FelipeFuhr/ffreis-platform-standards/issues/5)) ([4867938](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/4867938e060076431ce44903cb573f1338bb93c7))
* **ci:** install PyYAML before YAML validation step ([9fbd862](https://github.com/FelipeFuhr/ffreis-platform-standards/commit/9fbd862e5af0da06f98252a44c5f7e66e2fdd9cc))
