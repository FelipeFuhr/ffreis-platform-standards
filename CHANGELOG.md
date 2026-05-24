# Changelog

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
