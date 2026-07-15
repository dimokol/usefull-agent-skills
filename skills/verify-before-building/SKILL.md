---
name: verify-before-building
description: Create a feature branch the safe way. Fetch and check your trunk branch BEFORE building, so you never rebuild something the mainline already shipped on a stale base. Use whenever starting a new feature/fix, creating a feature branch or worktree, or before writing any non-trivial code. Triggers: "start a branch", "new feature branch", "begin work on X", "create a worktree", before the first `git checkout -b` / `git worktree add` of a task.
---

# verify-before-building

Creates a feature branch only after confirming the work isn't already shipped on `{trunk}`. Exists because a working branch (often called `dev` or `develop`) can sit many commits behind the true trunk (`{trunk}`, usually `main`) when work ships straight to trunk and isn't always back-merged. Building blind off a stale base risks rebuilding work that's already canonical.

## When to use

- Starting any new feature or non-trivial fix, before writing code.
- Before the first `git checkout -b` or `git worktree add` for a task.
- Paired multi-repo work (use the same branch name across repos you're touching together).

Skip for: trivial one-line edits on an already-checked-out branch, or work continuing an existing branch.

## Procedure

### 1. Identify the repos and the feature area

List which repos the work touches, and the concrete files/symbols/feature area you expect to build or change. You need that list for step 3.

### 2. Fetch and measure divergence from your trunk (every repo you'll touch)

```bash
git -C <repo> fetch origin {trunk} <your-base-branch> --quiet
BEHIND=$(git -C <repo> rev-list --count <your-base-branch>..origin/{trunk})
echo "<repo>: base branch is $BEHIND commits behind {trunk}"
```

- `BEHIND == 0` → your base branch already contains everything on `{trunk}`; safe to proceed to step 4.
- `BEHIND > 0` → **stop and do step 3** before building. Your base is missing trunk work; your area may already be there.

### 3. Verify your feature area isn't already on `{trunk}` (the key check)

For each file/symbol/area from step 1, look at `origin/{trunk}` (not your feature branch, not your local base branch):

```bash
git -C <repo> show origin/{trunk}:<path/to/file>            # does the file/impl already exist on trunk?
git -C <repo> grep -n "<Symbol|featureName|queryName>" origin/{trunk} -- '<likely paths>'
```

Also scan the repo's own docs/changelog for "shipped in #NNN (on {trunk})" style references, since they call out work already on trunk.

Decision:
- **Already on `{trunk}`** → do not rebuild it. Either (a) base your work on trunk's implementation (it's canonical) and only add the genuinely net-new delta, or (b) pause and get your base branch reconciled with trunk first, then rebase your net-new work onto the reconciled base. Record the lag so it gets reconciled.
- **Not on `{trunk}`** → genuinely net-new; proceed to step 4.
- **Partially on `{trunk}`** → split: keep only the net-new part; drop or align the rest to trunk's version.

If your base is badly behind trunk (large `BEHIND`), flag it. A reconcile merge is likely owed and may be owned by someone else, so coordinate before building on the stale base.

### 4. Create the branch

- Branch from your usual base (project convention) unless step 3 dictated basing on `{trunk}` instead.
- Paired multi-repo work uses the same branch name across repos.
- Use a worktree when you need to keep another branch checked out at the same time; never check out the same branch in two worktrees.

```bash
git -C <repo> checkout -b feat/<name> origin/<your-base-branch>
# or: git -C <repo> worktree add <path> -b feat/<name> origin/<your-base-branch>
```

### 5. Confirm and record

State the branch name, base, and the step-3 result ("verified `<area>` is NOT on `{trunk}`" / "found on `{trunk}`, basing on it / reconcile-first"). If your team tracks work in a task system, log it there before writing code.

## One-liner gate (paste before building)

```bash
for r in <repo-1> <repo-2> <repo-3>; do \
  p=<path-to-repo>/$r; \
  git -C "$p" fetch origin {trunk} <your-base-branch> -q 2>/dev/null && \
  echo "$r: base is $(git -C "$p" rev-list --count <your-base-branch>..origin/{trunk}) behind {trunk}"; done
```

Non-zero for a repo you're about to build in → run step 3 before writing code.

## Why this matters

A stale base branch feels safe because it still builds and passes tests. Divergence from trunk is invisible until you've already spent the effort. The cost isn't hypothetical: rebuilding a feature that trunk already shipped means the rebuilt half of the work gets discarded, and the diff has to be reconciled against the canonical version anyway. The fetch-and-grep in step 2-3 costs under a minute; skipping it can cost a whole session.
