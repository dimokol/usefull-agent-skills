---
name: worktree-qa-queue
description: Coordinate parallel git-worktree development with a single dedicated main checkout used for manual QA on a real running dev server before merge. Use when multiple branches are in flight across worktrees and a ready one needs to be handed off for human testing, when deciding where to run a dev server for verification, or when writing the promotion/lock/queue mechanics for a multi-branch workflow. Triggers: "promote this branch for testing", "who has the main checkout", "queue this for QA", "is the main checkout free", "set up a testing queue".
---

# worktree-qa-queue

A pattern for teams (or agents) that develop many branches in parallel via git worktrees, but only ever manually-test **one branch at a time** on a real dev server before it merges.

Pairs with the [`worktree-qa-guard`](../../hooks/worktree-qa-guard/) hook, which enforces the lock mechanically so the checkout-swap rule below isn't just a convention someone can forget.

## The problem this solves

Two things are true at once in active multi-branch development:

1. You want several branches moving forward simultaneously. Worktrees make that cheap, since each has its own working directory and doesn't block the others.
2. You want manual QA to happen against a real running dev server, on the actual checked-out branch, with no ambiguity about what's running and no risk of another branch's edits leaking in mid-test.

Those two wants conflict if you try to test directly inside a worktree: worktrees are disposable and numerous, dev servers are expensive to keep running per-worktree, and "which worktree is the tester looking at right now" becomes a coordination problem on its own.

The fix: keep worktrees for **development only**, and reserve the **main checkout** (the original, non-worktree clone of each repo) as the single QA surface. Development never happens there. Only one branch occupies it at a time. That gives you parallel throughput during development *and* a clean, contamination-free surface during QA. You don't sacrifice one for the other.

## The lifecycle

```
dev in a worktree
  → gates green (lint/build/test) + {reviewer} approved
  → ENQUEUE (added to the queue file, in order)
  → when the main checkout is FREE: PROMOTE
      (remove the worktree, checkout the branch in the main checkout,
       write the lock file, restart the dev server)
  → human tests on the running dev server, requests changes or approves
  → MERGE on the human's explicit go
  → main checkout returns to `{trunk}` + pull, lock removed, dev server restarted
  → next queued branch promotes
```

## Why this maximizes both speed and quality

- **Parallel worktrees keep throughput high.** Nobody blocks on "is the test environment free" while writing code. That question only matters at promotion time, not during development.
- **A single dedicated main checkout gives QA a ground-truth surface.** One real dev server, one branch, no "which worktree/port was that again," no risk of testing a half-merged mix of two people's edits.
- **The lock makes occupancy machine-checkable, not just a convention someone can forget.** A `git checkout` on the wrong branch while someone is mid-test silently pulls the rug out from under them. The running dev server now serves different code than what they're looking at, and the failure mode ("it broke!") is confusing to diagnose. A lock file plus a guard hook (see `worktree-qa-guard` in this hub) makes that mistake structurally impossible instead of relying on everyone remembering.
- **One-at-a-time avoids false signals.** If two branches shared the main checkout, a bug found during testing wouldn't tell you which branch caused it.

## Mechanics

### The lock file

A file at the repo root, e.g. `.qa-lock` (gitignored), written the moment a branch is promoted into the main checkout and removed the moment the human marks it done:

```
<branch-name>
promoted: <date>
pr: <url or number>
```

Its mere existence means "this checkout is OCCUPIED, do not swap its branch." A guard hook (`worktree-qa-guard`) can enforce this mechanically: block `checkout`/`switch`/`reset --hard`/`worktree` operations against a locked main checkout unless explicitly overridden.

### One branch per repo checkout at a time

Each repo's main checkout holds exactly one branch for QA. The next queued branch for that repo promotes only once the human frees the current one.

### Paired multi-repo branches promote together

If a change spans multiple repos (e.g. a backend change and its matching frontend change) under the **same branch name** in each, promote both branches into their respective main checkouts together, so integration testing runs against the real paired code rather than one branch against the other repo's `{trunk}`.

### No-surface work skips the queue

Work with nothing to manually look at (internal-only changes, pure config, changes with no paired user-facing branch) doesn't need to occupy a main checkout at all. Mark it "ready to merge, no manual test needed" and let it merge on explicit instruction without ever entering the queue.

### Restart the dev server after every promotion

Swapping the branch under a live dev server (`checkout` while `next dev` / a file-watching process is running) leaves the process serving a stale module graph. It can look like "the app won't load" or a mysterious hang, when really it's just serving mismatched code. **Every promotion needs an explicit "restart the dev server" step.** Don't assume hot-reload covers a branch swap.

### The queue file

A simple ordered list of what's waiting, so anyone (human or a fresh agent session with no memory of prior work) can pick up the process without more context:

```
## Queued

1. repo-a: branch `feat/x`, PR #123, approved <date>, prereqs: none
2. repo-b + repo-c (paired): branch `feat/y`, PR #124 / #125, approved <date>

## Currently promoted (main checkout occupied)

- repo-a: `feat/x`, promoted <date>, testing in progress

## Done

- repo-a: `feat/w`, merged <date>
```

Each entry should carry enough detail that a session with zero prior context can promote it: repo, branch, PR link, approval state, any prerequisites, and (if useful) which session originated the work.

## Common mistakes

- **Testing inside a worktree instead of the main checkout.** Defeats the purpose. You lose the single ground-truth surface and duplicate dev-server setup per worktree.
- **Swapping the main checkout's branch without checking the lock.** This is exactly what the `worktree-qa-guard` hook exists to prevent mechanically. Don't rely on remembering to check the queue file by hand.
- **Forgetting to restart the dev server after a promotion or after returning to `{trunk}`.** Looks like a broken app; it's a stale process.
- **Promoting the next branch before the human frees the current one.** One at a time, no exceptions. The whole point is avoiding cross-contamination.
- **Leaving the main checkout on a just-merged branch.** After merge, always return it to `{trunk}` and pull, so the slot's "free" state is unambiguous. A checkout left on a merged branch invites the next person to build on top of it by mistake.
