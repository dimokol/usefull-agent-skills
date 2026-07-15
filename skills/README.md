# 🛠 Skills

Reusable `SKILL.md` workflows. Install with the repo's `install.sh`; each skill's config (if any) goes in your project's CLAUDE.md.

| Skill | What it solves | Portability |
|---|---|---|
| [babysit-prs](babysit-prs/) | Drives an open PR to merge-ready: asks your reviewer, watches CI, applies review threads, loops until green + approved, then stops for your explicit merge. | 🟡 |
| [create-pr](create-pr/) | Opens a PR that already follows your conventions: body template, test-verification markers, task link, deploy notes. | 🟡 |
| [e2e-harness-patterns](e2e-harness-patterns/) | Patterns for a local ephemeral-stack e2e harness (Docker + seed + Playwright, affected-only runs). | 🟢 |
| [verify-before-building](verify-before-building/) | Cut a feature branch the safe way: fetch and check the trunk first so you never rebuild what the mainline already shipped. | 🟢 |
| [worktree-hygiene](worktree-hygiene/) | Session-start audit: disk free, Docker cache size, stale worktrees, branch divergence. Catches what silently eats a laptop. | 🟢 |
| [setup-audit](setup-audit/) | Periodic check your agent setup has not drifted, with weekly/deep modes and drift tripwires; catch ecosystem changes worth adopting. | 🟢 |
