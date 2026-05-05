---
name: babysit-prs
description: End-to-end PR finalization for one or more open GitHub PRs. Spawns one background subagent per PR; each subagent independently handles Copilot review (parallel across PRs), then runs verify-manual-tests serialized by a filesystem lock (Playwright is single-instance), and reports a compact JSON status. Returns control to the calling session immediately so the user can keep working. Use when the user lists 1+ PRs and asks to "babysit", "finalize", "ready for merge", "handle reviews and tests", "auto-handle PRs", or similar end-to-end PR closeout phrasing.
---

# babysit-prs

Take a list of open PRs to merge-ready autonomously. The calling session stays usable — N short-running background subagents do the actual work.

## Invocation

`/babysit-prs <pr-spec> [<pr-spec> ...]`

Each `<pr-spec>` is either:
- `<repo-key>:<pr-number>` — e.g. `be:188`
- A full GitHub PR URL — e.g. `https://github.com/Knorcedger/ridebly-be/pull/188`
- A bare PR number — only allowed when ALL specs in the list are bare and the user follows up to clarify which repo (or you can infer it from `gh pr view <n> --repo <each>` probing)

## Repo map

Treat this as the source of truth. To adapt the skill to a different project, just edit this table.

| Key | Path | GitHub repo | Quality gate command | Shared resources held by gate |
|-----|------|-------------|----------------------|-------------------------------|
| `be` | `~/Documents/Flarmio/Projects/ridebly/ridebly-be` | `Knorcedger/ridebly-be` | `npm run lint && npm run typecheck && PORT=4001 npm test` | `be-test-db` (TEST MongoDB is wiped on each suite boot — concurrent BE tests collide) |
| `fe` | `~/Documents/Flarmio/Projects/ridebly/ridebly-fe` | `Knorcedger/ridebly-fe` | `npm run lint && npm run build` | none |
| `client` | `~/Documents/Flarmio/Projects/ridebly/ridebly-client` | `Knorcedger/ridebly-client` | `npm run lint && npm run build` | none |

The `playwright` resource is held during `verify-manual-tests` for any PR with a `## Manual Testing` section, regardless of repo.

## Procedure (calling session)

1. **Parse + normalize** the PR list. For each entry, resolve to `{key, ghRepo, path, gateCmd, pr}`. URL: extract `owner/repo` from path, match into the repo map. `repo:pr`: direct lookup. Bare numbers: ask the user.

2. **Validate + filter:**
   ```bash
   gh pr view <pr> --repo <ghRepo> --json state,headRefName -q '{state,head:.headRefName}'
   ```
   Skip PRs that are not `OPEN`. Tell the user which were skipped. Also skip any PR for which `/tmp/babysit-<pr>-done` exists (resume support — re-runs do nothing for already-completed PRs).

3. **Precondition: main checkouts must be clean.** Phase B serializes on each repo's *main* working tree (Playwright runs against the user's existing dev servers, which point at the main checkout). For each repo touched by the PR list:
   ```bash
   git -C <path> status --porcelain
   ```
   If non-empty, REFUSE to dispatch. Tell the user precisely what's dirty (path + filename) and ask them to commit, stash, or restore before re-invoking. Do NOT auto-stash — those changes are theirs.

   Save each repo's current branch (for restore at end of run): `git -C <path> rev-parse --abbrev-ref HEAD > /tmp/babysit-<repo>-original-branch`.

4. **Clean stale locks** (defensive — don't inherit leftovers from a crashed previous run):
   ```bash
   for lock in /tmp/babysit-playwright.lock /tmp/babysit-tests-*.lock /tmp/babysit-main-*.lock; do
     [ -d "$lock" ] && rmdir "$lock" 2>/dev/null
   done
   ```

5. **Dispatch one background `general-purpose` Agent per remaining PR.** Each gets the entire `## Per-PR subagent task` block below as its prompt, with placeholders substituted. Use `run_in_background: true`. Dispatch all of them in a single message (parallel).

6. **Hand control back to the user.** One sentence: "Dispatched N agents. Each works in its own git worktree at `<path>--babysit-pr-<pr>`. They'll write status to /tmp/babysit-<pr>-status.json and return a JSON line. Continue with other work — I won't poll." That's it. Do not start polling.

7. **After all subagents return** (or on user request), restore each repo's main checkout to its original branch and prune any leftover worktrees:
   ```bash
   # For each repo touched:
   git -C <path> checkout "$(cat /tmp/babysit-<repo>-original-branch 2>/dev/null || echo dev)"
   git -C <path> worktree prune
   ```
   This leaves the user's environment in a sane state.

---

## Per-PR subagent task (passed verbatim with placeholders substituted)

> Substitute `{pr}`, `{ghRepo}`, `{path}`, `{gateCmd}`, `{branch}`.

You are a PR babysitter for ONE pull request. Your job is to take it from "open with potentially-pending Copilot review" to "merge-ready", then exit with a single-line JSON status.

**PR:** {pr} on {ghRepo}, branch `{branch}`, working tree at `{path}`.
**Quality gate command (run from {path}):** `{gateCmd}`

## NON-NEGOTIABLE RULES — read first

1. **Execute. Do not narrate. Do not plan out loud.** Every sentence in your response that isn't a tool call wastes tokens.
2. **Do not bail because a tool seems unavailable.** Deferred tools you'll need: `PushNotification` (for the per-PR completion alert). Load it ONCE at the very start with `ToolSearch query="select:PushNotification" max_results=1`. If `ToolSearch` itself fails or `PushNotification` won't load, skip just that one notification step — do NOT abort the whole task. Required tools that are always present: `Bash`, `Read`, `Edit`, `Write`, `Skill`. Polling = `Bash run_in_background` + `until` loop. Status updates = write to a file.
3. **Never invoke another subagent.** You are the leaf — do everything inline.
4. **Failure to make forward progress is not a valid outcome.** If something looks blocked, write a precise blocker to `/tmp/babysit-{pr}-status.json` and exit cleanly — do not produce vague speculation.
5. **Status file is your truth source.** Write `/tmp/babysit-{pr}-status.json` after every meaningful checkpoint so a re-run can resume.

## Step 0 — initialize

First, load the notification tool (one call, then proceed regardless of result):

```
ToolSearch query="select:PushNotification" max_results=1
```

Status file:

```bash
echo '{"pr":{pr},"phase":"start"}' > /tmp/babysit-{pr}-status.json
```

If `/tmp/babysit-{pr}-done` exists, exit immediately with `{"pr":{pr},"status":"already-done"}`.

## Step 0.5 — set up isolated worktree (THIS IS WHY THE SKILL DOESN'T COLLIDE)

Multiple PRs in the same repo would otherwise stomp on each other — each tries to `git checkout` a different branch in the same physical directory. To prevent that, every per-PR subagent works in its OWN git worktree.

```bash
WT="{path}--babysit-pr-{pr}"

# Create worktree (idempotent — if it exists from a previous interrupted run, reuse it)
if [ ! -d "$WT" ]; then
  git -C {path} worktree add "$WT" {branch}
fi

cd "$WT"

# Symlink node_modules from the main checkout — gates only READ from node_modules,
# they never write. This avoids a 1-2 minute `npm install` per worktree. Safety
# rule: NEVER run `npm install` / `npm ci` inside a worktree. If a gate complains
# about a missing dependency, that's a real signal, not a setup failure.
if [ ! -e ./node_modules ] && [ -d "{path}/node_modules" ]; then
  ln -sf "{path}/node_modules" ./node_modules
fi

# Symlink .env (gitignored) so backend / frontend can read the right config.
if [ ! -e ./.env ] && [ -f "{path}/.env" ]; then
  ln -sf "{path}/.env" ./.env
fi

# (Optional, BE only) symlink .env.local / .env.development if your repo uses them.
```

For the rest of Steps 1–3, "the working tree" means `$WT`. If `/tmp/babysit-{pr}-review-done` already exists, you can skip Phase A entirely and jump to Step 4 — but you still need the worktree set up because Phase A's pushed commits live there.

## Step 1 — wait for Copilot's review (cap 30 min)

Use `Bash run_in_background` with this exact pattern:

```bash
START=$(date +%s)
until [ "$(gh api repos/{ghRepo}/pulls/{pr}/reviews 2>/dev/null | jq '[.[]|select(.user.login=="copilot-pull-request-reviewer[bot]")]|length' 2>/dev/null)" -gt 0 ]; do
  if [ $(( $(date +%s) - START )) -gt 1800 ]; then echo "TIMEOUT"; exit 1; fi
  sleep 60
done
echo "REVIEW_FOUND"
```

Use `BashOutput` to check for `REVIEW_FOUND` or `TIMEOUT`. If TIMEOUT, write `{"pr":{pr},"phase":"review-wait","blocker":"copilot review never arrived in 30 min"}` to status, skip to Step 4 (manual tests can still run).

## Step 2 — fetch + handle Copilot comments

```bash
gh api repos/{ghRepo}/pulls/{pr}/comments \
  | jq '[.[] | select(.user.login=="copilot-pull-request-reviewer[bot]") | {id, node_id, path, line, body, in_reply_to_id}]' \
  > /tmp/babysit-{pr}-comments.json
```

For each top-level comment (skip ones with non-null `in_reply_to_id`):

a) `Read` the file at the line referenced.

b) Decide validity per the repo's CLAUDE.md PR-Workflow conventions (you're in `{path}` so the harness already loaded it). Use judgment — Copilot is often wrong about niche or context-dependent items.

c) **If valid**: implement the fix. After all valid fixes for THIS PR, run `{gateCmd}` from `{path}`. If gates pass, commit (no `--no-verify`, no `--amend`) and push:
   ```bash
   git add -A && git commit -m "fix: address Copilot review on PR #{pr}" && git push
   ```
   Capture the commit hash for the reply.

d) **Reply** to the thread:
   ```bash
   gh api -X POST repos/{ghRepo}/pulls/{pr}/comments/<comment-id>/replies \
     -f body='<commit hash + 1-line rationale OR clear non-applying reason>'
   ```

e) **Resolve** the thread:
   ```bash
   gh api graphql -f query='mutation{resolveReviewThread(input:{threadId:"<node_id>"}){thread{id}}}'
   ```

After every comment is replied to + resolved:
- Touch `/tmp/babysit-{pr}-review-done`
- Write status: `{"pr":{pr},"phase":"review-done","applied":["<sha>",...],"declined":N,"blockers":[...]}`

## Step 3 — verify quality gates (no Copilot fix path)

If your repo holds a shared-resource gate (see the "Shared resources held by gate" column in the repo map), acquire that lock before running `{gateCmd}`:

```bash
# Only if the repo map says this repo's gate touches a shared resource (e.g. `be-test-db`)
START=$(date +%s)
until mkdir /tmp/babysit-tests-{resource-name}.lock 2>/dev/null; do
  if [ $(( $(date +%s) - START )) -gt 3600 ]; then echo "GATE_LOCK_TIMEOUT"; exit 1; fi
  sleep 30
done
echo "$$" > /tmp/babysit-tests-{resource-name}.lock/owner-pid
trap 'rm -rf /tmp/babysit-tests-{resource-name}.lock' EXIT
```

For Ridebly's `be` repo this means `mkdir /tmp/babysit-tests-be-test-db.lock`. Other repos: skip the lock entirely.

Then run `{gateCmd}`. If it fails, classify the failure before bailing:

- **Looks like resource collision** (e.g. test output shows MongoDB connection wiped, fixtures reset mid-run, "tests clear all collections on startup"): you didn't have the lock or the lock dance failed. Wait 30s, re-acquire, re-run ONCE.
- **Fail from your own change in Step 2**: read the error, fix it in code, commit + push as an extra commit, re-run gates.
- **Fail from pre-existing brokenness on the branch**: write a blocker `{"blocker":"gate failing pre-existing on <branch>: <one-line summary>"}` and skip Step 4.

Whether or not you ran a fix in Step 2, you ALWAYS run gates at least once to confirm green-on-merge.

After gates green, release the lock immediately (`rm -rf /tmp/babysit-tests-{resource-name}.lock`) so other PRs can proceed — don't hold it through Step 4.

## Step 4 — verify-manual-tests (main-checkout branch dance + Playwright lock)

First, check whether this PR has a `## Manual Testing` section at all:

```bash
gh pr view {pr} --repo {ghRepo} --json body -q '.body' | grep -q '## Manual Testing' && echo "HAS_MT" || echo "SKIP_MT"
```

If `SKIP_MT`, jump to Step 5 — there's nothing to drive Playwright through.

Otherwise: Phase B runs against the user's existing dev servers (which serve from `{path}` — the *main* checkout, not your worktree). So you need to (a) lock the main checkout against other PRs, (b) put it on this PR's branch so the dev server's --watch / HMR rebuilds, then (c) acquire Playwright and run the test. Releases happen in reverse.

```bash
# (a) Acquire main-checkout lock for THIS repo (not the worktree — the original)
START=$(date +%s)
until mkdir /tmp/babysit-main-{key}.lock 2>/dev/null; do
  if [ $(( $(date +%s) - START )) -gt 14400 ]; then echo "MAIN_LOCK_TIMEOUT"; exit 1; fi
  sleep 30
done

# (b) Verify main is clean — the user-precondition check from the calling session
# could have raced with the user editing files in between
DIRTY=$(git -C {path} status --porcelain)
if [ -n "$DIRTY" ]; then
  rmdir /tmp/babysit-main-{key}.lock
  # BLOCKER — write status, skip Step 4, continue to Step 5 with tests:"0/N"
  echo '{"pr":{pr},"phase":"phase-b-precheck","blocker":"main checkout {key} dirty: '"$DIRTY"' — please clean and re-invoke for this PR"}' > /tmp/babysit-{pr}-status.json
  # SKIP forward to Step 5 (notification) and return BLOCKED
fi

# (c) Switch main to this PR's branch — the user's dev server (--watch / HMR) will rebuild
git -C {path} checkout {branch}

# Give the dev server time to pick up the change. For Next.js HMR ~3s; for BE
# node --watch ~2s. Be generous — manual tests against stale code waste the run.
sleep 8
```

Now acquire the Playwright lock atomically (POSIX `mkdir` is atomic — exactly one waiter wins per attempt):

```bash
START=$(date +%s)
until mkdir /tmp/babysit-playwright.lock 2>/dev/null; do
  if [ $(( $(date +%s) - START )) -gt 14400 ]; then echo "LOCK_TIMEOUT"; exit 1; fi
  sleep 30
done
echo "$$" > /tmp/babysit-playwright.lock/owner-pid
trap 'rm -rf /tmp/babysit-playwright.lock' EXIT
```

(LOCK_TIMEOUT after 4h means another PR's tests have been hung; give up gracefully.)

With the lock held, invoke the `verify-manual-tests` skill via the `Skill` tool. Pass the PR number ({pr}) and repo ({ghRepo}). It runs inline, drives Playwright through the PR's `## Manual Testing` section against the user's existing dev servers, flips checkboxes, returns when done.

After it returns, release locks in reverse acquisition order:
```bash
rm -rf /tmp/babysit-playwright.lock
rm -rf /tmp/babysit-main-{key}.lock
touch /tmp/babysit-{pr}-tested
touch /tmp/babysit-{pr}-done
```

Do NOT switch the main checkout back to its original branch — the calling session does that once at the end of the whole run, after all PRs finish (avoids needless thrash if the next PR's branch happens to share the same parent).

## Step 5 — fire completion notification

If `PushNotification` was loaded successfully in Step 0, call it ONCE before returning. This is the per-PR alert the user is waiting for — it triggers their Claude Notifications extension (or any other notification hook they have) and surfaces an OS banner with a clickable focus action.

Pick the title/message based on the final status:

```
PushNotification(
  title="babysit-prs",
  message="{ghRepo} #{pr} — READY ✅"
)
```

or, if blocked:

```
PushNotification(
  title="babysit-prs",
  message="{ghRepo} #{pr} — BLOCKED ⚠ <one-sentence reason>"
)
```

Keep the message under 120 chars so it renders cleanly in OS banners on all platforms. If `PushNotification` isn't available, skip this step silently.

## Step 5.5 — clean up your worktree

Before returning, prune the worktree you created in Step 0.5. Failure to do this leaves orphan worktrees that confuse future `git worktree list` calls.

```bash
cd /tmp  # leave the worktree dir before removing it
git -C {path} worktree remove --force "{path}--babysit-pr-{pr}" 2>/dev/null || true
```

If the remove fails (e.g. you have uncommitted experimental changes you want to keep), DON'T retry forcibly — leave the worktree in place and add a note to the blockers list: `"worktree at <path> kept due to local-only changes; remove manually when reviewed"`. The calling session's final cleanup will skip it.

## Step 6 — final return

Return EXACTLY ONE JSON line, nothing else, no narration before or after:

```json
{"pr": {pr}, "status": "READY|BLOCKED", "applied": ["sha", ...], "declined": N, "tests": "X/Y", "blockers": ["short reasons", ...]}
```

`status` is `READY` only when (1) all Copilot threads replied + resolved, (2) gates green, (3) every `- [ ]` in the PR's `## Manual Testing` is `- [x]`. Otherwise `BLOCKED`.

---

## Stop conditions (each per-PR subagent)

- **5-hour rate-limit guard.** If any tool call returns a 429 / "rate limit" / "usage limit" error, write a blocker `{"phase": "<current>", "blocker": "rate limit hit"}` to status and exit cleanly — do not retry.
- 4 hours wall-clock with no marker advancing → write blocker, exit.
- Same individual operation fails 3× in a row WITH 3 DIFFERENT recovery strategies → write blocker for that operation only, continue to the next.
- A Copilot comment requires a product decision you can't make alone → reply to the thread saying so + leave it unresolved + add to blockers list. Do NOT resolve threads you skipped.

## Failure classification — when to fix vs report

The defining principle: **never bail without trying**. Either fix it (in-scope, local) or report a precise one-line recovery command (the action belongs to the user's domain). Don't just say "tests failed" and exit — that wastes the run.

### AUTO-FIX — implement, push, retry (don't ask)

| Symptom | Action |
|---|---|
| Test failures with N collisions, fixtures wiped mid-run, "duplicate key on startup" | Resource-collision pattern. Acquire the relevant lock from Step 3, re-run gates serially. |
| Lint / typecheck / build error introduced by your own commit in Step 2 | Read the error, fix it, commit as an extra patch, re-run. |
| `verify-manual-tests` finds a real bug in PR-touched code (e.g. dialog state not reloading after save, raw enum shown instead of formatted label) | Read the relevant file, implement the obvious fix, commit `fix: <one-line> — found via PR #{pr} manual test`, push, re-run that checkbox. Hard cap: 3 attempts per checkbox, the 3rd must be a *different* fix. |
| Missing test data (no reservations exist for "open a reservation" checkbox) | Use the verify-manual-tests Step 5 3-tier seed protocol. |
| Transient gh / git network blip | Wait 10s, retry once. |

### REPORT BLOCKER — do NOT touch (the user owns this)

| Symptom | Blocker line in your status |
|---|---|
| `Cannot find module './vendor-chunks/*.js'` (stale Next.js cache) | `"stale .next in <repo> — run 'rm -rf <repo>/.next' and restart your 'npm run dev', then re-invoke /babysit-prs"` |
| Dev server returns 502 / connection refused | `"<repo> dev server (port <n>) is down — please 'npm run dev', then re-invoke"` |
| Database schema out of sync with code (e.g. unknown collection / missing field) | `"DB schema mismatch in <repo> — needs migration, manual review required"` |
| Copilot comment requires design / product decision | `"PR #{pr} thread <url>: needs your call — <one-line summary>"` |
| Fix would expand scope (cross-cutting refactor, dep upgrade, schema migration, > ~5 files) | `"out of scope for this PR — suggest follow-up PR for <what>"` |

### KEY DISTINCTION

You own: code under `{path}` (the PR's working tree), gh API, git, your own background processes.
User owns: dev servers running on the host, build caches (`.next`, `dist`, `node_modules` reinstall), DB schemas, anything they explicitly asked you not to touch.

If a fix would require touching anything in the user-owned column, write the blocker with the exact recovery command and move to the next thing. Don't pause the whole subagent waiting — just blocker that one item and continue.

---

## Token-economy notes (calling session perspective)

- Calling session does N background `Agent` dispatches in one message. Each dispatch is ~2KB of prompt; total dispatch cost is bounded.
- Each subagent returns ONE JSON line (~250 chars). Total return cost: N × 250 chars.
- All gh / git / file work happens inside subagent contexts — your session never reads the repo files.
- `verify-manual-tests` runs INSIDE each subagent (not as a sub-subagent), inheriting that skill's own efficient tool-use rules.
- Marker files in `/tmp/` provide resume support. To wipe and re-run cleanly: `rm /tmp/babysit-*`.

## Plays nicely with Claude Code notification extensions

If the user has a Claude Code notification extension installed (e.g. `dimokol.claude-notifications` / "Claude Notifications" — VS Code marketplace), each per-PR completion fires `PushNotification` from inside the per-PR subagent. That hits the extension's `Notification` hook with the message above, and the user gets:

- Sound + OS banner (or in-window toast if VS Code is focused).
- A clickable "Focus Terminal" action that jumps to the calling session's terminal.
- Stage-dedup: each subagent has a distinct `session_id`, so the extension treats every PR completion as a fresh stage — no incorrect suppression, no duplicate noise.

Net behavior:
- N background subagents → exactly N completion notifications (one per PR), each with a tailored "READY ✅ / BLOCKED ⚠" message.
- The calling (parent) session's eventual `Stop` hook fires its own notification when the user's next idle-after-everything-completes moment arrives — that's the natural "all done" prompt.

**Token cost of this integration: one `ToolSearch` + one `PushNotification` per subagent (≈80 tokens total per PR).** Everything else is the extension's job.

If no notification extension is installed, the user just sees no banners — the workflow itself isn't affected. The PR list still lands in the parent session via the JSON returns.

## When to use vs not

**Use when:** 1+ open PRs need both Copilot-review handling and manual testing taken to merge-ready.
**Don't use when:** PR has no Copilot review enabled AND no `## Manual Testing` section — there's nothing to babysit. Run `verify-manual-tests` directly for a single test pass.
