## Making fleet-wide changes

1. Update the relevant file in this repo
2. Open a PR — CI validates JSON/YAML/shell automatically
3. Merge to main
4. Renovate runs pick up changes fleet-wide; lefthook `remotes:` pulls on next `lefthook install`
