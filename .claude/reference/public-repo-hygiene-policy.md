## Public repo hygiene policy

All repos under `FelipeFuhr/` that are **publicly visible** must never expose internal
architecture details beyond what external contributors need to contribute. This policy
was established after a 2026-05-29 audit found private repo names, internal domain
patterns, and an unredacted workspace `CLAUDE.md` committed to public repos.

### What IS acceptable in public repos

- References to other **public** repos (`ffreis-website-compiler`, `ffreis-siteops`,
  `ffreis-website-deployer`, `ffreis-platform-standards`, etc.)
- Public production domains (`ffreis.com`, `flemming.com.br`, `petlook.app`,
  `petlook.ai`)
- Generic descriptions: "the fleet inventory", "a private consumer", "internal infra",
  "private data repo", "the website Lambdas repo"
- Secret **names** (not values): `AWS_DEPLOY_ROLE_ARN`, `CF_DISTRIBUTION_ID`, etc.
- Operational patterns (branching model, CI rules, hook configs) that don't name private resources

### What is NOT acceptable in public repos

- **Private repo names**: any repo not listed on the public profile README
  (e.g., `ffreis-website`, `flemming-website`, `petlook-data`, `ffreis-website-inventory`,
  `ffreis-rust-shared`, `ffreis-tracker-sdk`, all `*-infra` repos)
- **Internal dev domains**: `*.ffreis.com` subdomains used for dev routing
  (e.g., `flemming.ffreis.com`, `dev.ffreis.com`)
- **Internal naming patterns**: AWS resource-naming conventions, S3 bucket patterns,
  API Gateway naming conventions (e.g., `-api-dev`)
- **Workspace context files**: `workspace/CLAUDE.md`, `workspace/AGENTS.md` — these
  contain the full internal platform map and MUST be gitignored. The `workspace/`
  directory is in this repo's `.gitignore` to prevent accidental commits.
- **AWS resource IDs**: hardcoded bucket names, CloudFront distribution IDs,
  account IDs, role ARNs (even in comments)
- **Real credential values**: any token, key, or secret (even expired ones)

### Verification

Run the fleet-wide hygiene scan to catch private refs in public repos:

```bash
bash quality-kit/scripts/check-public-repo-hygiene.sh
```

The scan checks all repos whose remote points at `FelipeFuhr/` and prints
`[FAIL]` for any file containing known private identifiers.

### Fixing a leak

1. Replace private names with generic descriptions (see "What IS acceptable" above).
2. Check git history for the same string: `git log -p --all -S '<private-name>'`
3. If history contains the leak, use `git filter-repo --path <file> --invert-paths`
   or `git filter-repo --replace-text <expressions-file>` to purge all branches.
4. Force-push all affected branches (requires user confirmation for safety).
5. Run `git reflog expire --expire=now --all && git gc --prune=now` on the local clone.
6. Ask GitHub Support to run garbage collection on the remote if the leak was live.

