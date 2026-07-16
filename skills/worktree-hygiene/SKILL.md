---
name: worktree-hygiene
description: Run a session-start storage + worktree + branch-divergence health audit for a multi-repo project. Reports disk free, Docker cache size, worktrees whose PR is merged (and therefore removable), idle node_modules in sibling project folders, and how far each repo's base branch is behind trunk (so you don't build a feature on a stale base that trunk already shipped). Outputs an action list, not autonomous deletes. Use at session start, before starting feature work, before dispatching PR review, or any time the laptop feels tight. Triggers: "health check", "storage check", "disk check", "audit worktrees", "am I low on disk", "is my base branch behind trunk".
---

# worktree-hygiene

A read-only audit that surfaces the disk-pressure signals that cause out-of-space incidents in projects that use worktrees and local Docker-based test harnesses heavily. Never deletes anything itself; it produces an actionable summary for the user to decide on.

## What it checks

| Signal | Threshold | Why it matters |
|---|---|---|
| Free disk on `/` | <10 GB → RED, <20 GB → AMBER | A Docker-based e2e harness build alone typically needs a few GB of headroom; running out mid-build leaves stale locks and uncommitted edits in force-removed worktrees |
| Docker buildx cache | >5 GB → AMBER, >10 GB → RED | Without an explicit cap the cache trends upward indefinitely |
| Total Docker disk usage | >30 GB → AMBER | `docker system df` total; when combined with low free disk, primary prune candidate |
| Worktrees (each repo) | any whose branch has a merged PR | Once a branch's PR is merged, its worktree is safe to remove |
| Worktrees (each repo) | any whose branch has no PR (orphan) | May be a forgotten experiment |
| Sibling `node_modules` (non-worktree project folders) | any large idle install | Projects living alongside your worktrees but not part of the active work; installs left over from past sessions can sit idle for weeks, hundreds of MB each |
| Framework build caches (`.next`, `.turbo`, `dist`, etc.) | large (hundreds of MB+) | Safe to delete, rebuilds on next dev run |
| Test-runner artifact dirs (Playwright/Cypress `*-report`, `test-results`) | exists, especially >1 day old | Session artifacts from past runs; dead weight once the run is reviewed |
| Orphan long-running dev processes | any with PPID=1 matching your dev-server command | Each holds open connections/timers; indicates a `--watch`-style process failed to receive the shell's exit signal on close |
| Base branch behind trunk (per repo) | any (`<base>..origin/{trunk}` > 0) → AMBER; large → RED | A base branch lagging trunk means feature work cut from it can rebuild something trunk already shipped. Surface it before building so the `verify-before-building` check (grep your area against `origin/{trunk}`) or a reconcile merge happens first. |

## Procedure

1. Run all checks **in parallel** via a single shell invocation where possible (independent reads).
2. Format the output as a table with three columns: Signal | Value | Action.
3. The Action column is one of: `OK`, `consider <command>`, or `BLOCKER: run <command> before <heavy operation>`.
4. Never auto-delete. Even if a signal is RED, the user must approve cleanup.

## Commands the audit uses

```bash
# Disk
df -h /

# Docker (gracefully handle daemon-down)
docker system df 2>/dev/null
docker buildx du --filter "type=regular" 2>/dev/null | tail -3

# Worktrees + merge state (repeat per repo)
git -C <repo-path> worktree list --porcelain
gh pr list --repo <org>/<repo> --state merged --limit 50 --json number,headRefName

# Sibling + cache sizes
du -sh <projects-parent>/*/node_modules 2>/dev/null
du -sh <repo-path>/.next 2>/dev/null
du -sh <repo-path>/.playwright-mcp 2>/dev/null

# Orphan dev-server processes (PPID=1); adjust the pattern to your dev command
echo "=== Orphan dev processes (PPID=1) ==="
ps -eo pid,ppid,etime,%cpu,%mem,command | awk '$2==1 && /<your dev-server command pattern>/'
ORPHAN_COUNT=$(ps -eo pid,ppid,command | awk '$2==1 && /<your dev-server command pattern>/' | wc -l | tr -d ' ')
echo "Total: $ORPHAN_COUNT orphans"

# base branch behind trunk (per repo); surfaces stale-base rebuild risk
echo "=== base behind {trunk} ==="
for r in <repo-1> <repo-2> <repo-3>; do
  p=<projects-parent>/$r
  git -C "$p" fetch origin {trunk} <your-base-branch> -q 2>/dev/null
  echo "$r: base is $(git -C "$p" rev-list --count <your-base-branch>..origin/{trunk} 2>/dev/null) commits behind {trunk}"
done
```

## When the daemon is down

If `docker system df` returns EOF or hangs, don't wait. Report `BLOCKER: Docker daemon unresponsive, restart it` and continue with the non-Docker checks. The remaining signals still give a meaningful picture.

## Output template

```
worktree health check (<date>)

Disk:         <free GB>/<total GB> free  | <OK/AMBER/RED>
Docker:       <total GB> total, buildx <GB> | <OK/AMBER/RED>

Worktrees to remove (PR merged):
  <repo>:
    <branch> (PR #N, merged <date>)  → git worktree remove <path>

Orphan processes:
  <N> orphans (etime <range>, ~<CPU>% aggregate, ~<MB> RSS aggregate)
                                     → kill with: ps -eo pid,ppid,command | awk '$2==1 && /<pattern>/ {print $1}' | xargs kill

Idle caches:
  <repo>/.next (<GB>)                → rm -rf <path>     (rebuilds on next dev)
  <sibling>/node_modules (<GB>)      → rm -rf <path>     (reinstalls in <seconds>)

Suggested cleanup order:
  1. <highest-impact action>
  2. <next>
  …

Estimated recovery: ~<GB> if all suggestions applied.
```

## What this skill is NOT

- It is **not** a fix-it skill. It surfaces problems and proposes commands; the user runs them (or asks the agent to).
- It does **not** prune Docker on its own. That requires explicit user approval.
- It does **not** touch the user's running dev servers or any process it doesn't recognize as its own leftover.

## Worktree retention rules (general)

- **Active work**: keep the worktree (and its installed dependencies) until the PR is merged.
- **PR open, no in-flight edits**: keep the worktree for fast review iterations, but consider dropping heavy installed dependencies; reinstalling is quick.
- **PR merged**: remove the worktree; don't keep merged-branch worktrees around.
- **Bulk audit**: `git worktree list` at session start, cross-reference against merged PRs for removal candidates.
