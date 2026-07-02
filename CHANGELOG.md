# Changelog

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
