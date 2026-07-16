# worktree-qa-guard (PreToolUse hook)

Blocks swapping a repo's main-checkout branch while it's locked for manual QA. Pairs with the [`worktree-qa-queue`](../../skills/worktree-qa-queue/) skill: read that first for the full pattern this hook enforces.

## Why

In the `worktree-qa-queue` pattern, development happens in worktrees and exactly one branch at a time occupies the main checkout for manual testing against a real running dev server. If someone (or an agent) checks out a different branch in that main checkout mid-test, the dev server silently starts serving different code than what the tester is looking at. That's a confusing failure mode that looks like "it broke" when really the ground shifted underneath them. A prompt-level rule ("don't touch the main checkout while it's locked") is easy to forget in a long session. This hook makes it structurally impossible instead.

## What it blocks

Branch-swapping `git` operations (`checkout`, `switch`, `reset --hard`) targeting a repo whose root has a `.qa-lock` file present.

## What it does NOT block

- Read-only git (`fetch`, `log`, `status`, `diff`, `show`, `merge-base`).
- Every `git worktree` subcommand (`add`, `remove`, `prune`, `list`). None of them change the main checkout's branch, so creating or cleaning up worktrees is always safe.
- Any path that looks like a worktree (matches `*--wt/*`, `*--wt`, or `*--qa-*`). The guard only cares about the main checkout.
- Any repo whose root has no `.qa-lock` file. An unlocked checkout is free to switch branches normally.
- `git checkout -- <file>` and a plain `git reset` (soft/mixed). Those aren't branch swaps.

## The lock file

A file named `.qa-lock` at the repo root (gitignore it), written the moment a branch is promoted into the main checkout for testing, removed the moment the human marks it done. Its content is read-only informational. The hook shows the first line in its denial message:

```
<branch-name>
promoted: <date>
pr: <url or number>
```

## Configuration

| Variable | Purpose |
|---|---|
| `ALLOW_QA_CHECKOUT=1` | Prefix on the command itself: explicit, deliberate override. Set only after the human has freed the slot (removed the lock) or explicitly instructed the swap. |

## Install

1. Copy the script somewhere stable and make it executable:

   ```bash
   mkdir -p ~/.claude/hooks
   curl -fsSL https://raw.githubusercontent.com/dimokol/usefull-agent-skills/main/hooks/worktree-qa-guard/hook.sh \
     -o ~/.claude/hooks/worktree-qa-guard.sh
   chmod +x ~/.claude/hooks/worktree-qa-guard.sh
   ```

2. Register it in `~/.claude/settings.json` (merge with your existing hooks):

   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             { "type": "command", "command": "sh \"$HOME/.claude/hooks/worktree-qa-guard.sh\"" }
           ]
         }
       ]
     }
   }
   ```

3. Write `.qa-lock` at a repo's root when you promote a branch into it for testing (see `worktree-qa-queue`), and remove it when the human marks the branch done.

4. Verify: with a `.qa-lock` present, ask the agent to `git checkout main` inside that repo. It should be denied, while `git fetch` and `git worktree add ../repo--wt/some-branch some-branch` both pass.

Requires `jq`. Pairs with [`worktree-qa-queue`](../../skills/worktree-qa-queue/) for the full lifecycle (promote → lock → test → merge → unlock → return to `{trunk}`).
