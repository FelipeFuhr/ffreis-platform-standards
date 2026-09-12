## Workspace docs (`workspace/`)

Agent-facing docs that live at the workspace root (above the individual
repos) — `AGENTS.md` (agent-agnostic) and `CLAUDE.md` (Claude-specific).
Tracked here so they're versioned and shareable rather than loose files
on a single machine.

| File | Purpose |
|---|---|
| `workspace/AGENTS.md` | Workspace-level guide for any AI assistant (Codex, Cursor, Claude, …). Mirrors agent-relevant rules from `CLAUDE.md` in agent-agnostic phrasing. |
| `workspace/CLAUDE.md` | Claude-specific workspace guide. Auto-loaded by Claude Code when invoked at workspace root. |

Both files reference relative paths under the workspace root (e.g.
`platform/ffreis-platform-standards/scripts/...`), so they're portable
across machines that follow the same layout.

### Install at workspace root

The expected pattern is to symlink them in so changes here propagate
without manual copy:

```bash
cd /path/to/workspace-root
ln -sf platform/ffreis-platform-standards/workspace/AGENTS.md AGENTS.md
ln -sf platform/ffreis-platform-standards/workspace/CLAUDE.md CLAUDE.md
```

(If you'd rather copy than symlink — e.g. so you can tweak per-machine —
just `cp` them. You'll fall behind on upstream edits then; treat the
copies as a snapshot.)
