---
paths:
  - "golangci/**"
---

# golangci standard

Copy `golangci/standard.yml` to `.golangci.yml` in each Go repo. The config is golangci-lint
v2 format. The only value that may need adjustment per repo is `goimports.local-prefixes`
(default is `github.com/ffreis`, which covers all repos in this org).
