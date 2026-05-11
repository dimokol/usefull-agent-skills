---
name: babysit-prs
description: End-to-end PR finalization for one or more open GitHub PRs. Spawns one background subagent per PR; each subagent independently handles Copilot review (parallel across PRs), runs the repo's quality gate, and — for FE PRs — runs the local Playwright e2e suite (serialized by a filesystem lock because the harness binds host ports 3100/4100). Returns control to the calling session immediately. Use when the user lists 1+ PRs and asks to "babysit", "finalize", "ready for merge", "handle reviews and tests", "auto-handle PRs", or similar end-to-end PR closeout phrasing.
---

# babysit-prs

Take a list of open PRs to merge-ready autonomously. The calling session stays usable — N short-running background subagents do the actual work.

## Project-specific assumptions (Ridebly)

This skill was authored against the Ridebly monorepo. To reuse elsewhere, edit:

- The **repo map** below.
- The **e2e command + lock** in the per-PR task (Ridebly's FE uses `npm run test:e2e:full`, binds host ports 3100/4100, base branch `dev`).
- Any base-branch references (`dev`).

## Invocation

`/babysit-prs <pr-spec> [<pr-spec> ...]`

Each `<pr-spec>` is either:
- `<repo-key>:<pr-number>` — e.g. `be:188`
- A full GitHub PR URL — e.g. `https://github.com/Knorcedger/ridebly-be/pull/188`
- A bare PR number — only allowed when ALL specs in the list are bare and the user clarifies which repo

## Repo map

| Key | Path | GitHub repo | Quality gate command | Has e2e suite? | Shared resources held by gate |
|-----|------|-------------|----------------------|----------------|-------------------------------|
| `be` | `~/Documents/Flarmio/Projects/ridebly/ridebly-be` | `Knorcedger/ridebly-be` | `npm run lint && npm run typecheck && PORT=4001 npm test` | no | `be-test-db` (TEST MongoDB is wiped on each suite boot) |
| `fe` | `~/Documents/Flarmio/Projects/ridebly/ridebly-fe` | `Knorcedger/ridebly-fe` | `npm run lint && npm run build` | **yes** — `npm run test:e2e:full` | `e2e-stack` (host ports 3100/4100 — docker compose, single binding) |
| `client` | `~/Documents/Flarmio/Projects/ridebly/ridebly-client` | `Knorcedger/ridebly-client` | `npm run lint && npm run build` | no | none |

## Procedure (calling session)

1. **Parse + normalize** the PR list to `{key, ghRepo, path, gateCmd, hasE2E, e2eCmd, pr}`.

2. **Validate + filter:**
   ```bash
   gh pr view <pr> --repo <ghRepo> --json state,headRefName -q '{state,head:.headRefName}'
   ```
   Skip PRs that are not `OPEN`. Skip any PR for which `/tmp/babysit-<pr>-done` exists.

3. **Clean stale locks:**
   ```bash
   for lock in /tmp/babysit-e2e-stack.lock /tmp/babysit-tests-*.lock; do
     [ -d "$lock" ] && rmdir "$lock" 2>/dev/null
   done
   ```

4. **Dispatch one background `general-purpose` Agent per remaining PR**, passing the Per-PR task block verbatim with placeholders substituted. Use `run_in_background: true`. Send all dispatches in a single message.

5. **Hand control back to the user.** One sentence: "Dispatched N agents in worktrees under `<path>--babysit-pr-<pr>`. Status lands in `/tmp/babysit-<pr>-status.json`. Continue with other work — I won't poll."

6. **After all subagents return** (or on user request), prune leftover worktrees:
   ```bash
   for path in <each touched repo>; do
     git -C "$path" worktree prune
   done
   ```

The calling session never modifies the user's main checkouts — every subagent works in its own worktree. No branch switching of the main checkout is required (deterministic e2e specs replace the Playwright-MCP "drive the live dev server" flow that the old verify-manual-tests skill used).

---

## Per-PR subagent task (passed verbatim with placeholders substituted)

> Substitute `{pr}`, `{ghRepo}`, `{path}`, `{gateCmd}`, `{hasE2E}` (`true`/`false`), `{e2eCmd}`, `{branch}`.

You are a PR babysitter for ONE pull request. Take it from "open with potentially-pending Copilot review" to "merge-ready", then return ONE JSON status line.

**PR:** {pr} on {ghRepo}, branch `{branch}`, working tree at `{path}`.
**Quality gate (from worktree):** `{gateCmd}`
**E2E suite:** {hasE2E} ({e2eCmd} when true)

## NON-NEGOTIABLE RULES

1. **Execute. Do not narrate.** Every sentence that isn't a tool call wastes tokens.
2. **Load `PushNotification` once at start** via `ToolSearch query="select:PushNotification" max_results=1`. If unavailable, skip the notification step at the end — do not abort.
3. **Never invoke another subagent.** You are the leaf.
4. **Status file is your truth source.** Write `/tmp/babysit-{pr}-status.json` after every meaningful checkpoint.
5. **No `--no-verify`, no `--amend`.** Every fix is a new commit.

## Step 0 — initialize

```
ToolSearch query="select:PushNotification" max_results=1
```

```bash
echo '{"pr":{pr},"phase":"start"}' > /tmp/babysit-{pr}-status.json
[ -f /tmp/babysit-{pr}-done ] && { echo '{"pr":{pr},"status":"already-done"}'; exit 0; }
```

## Step 0.5 — isolated worktree

```bash
WT="{path}--babysit-pr-{pr}"
if [ ! -d "$WT" ]; then
  git -C {path} worktree add "$WT" {branch}
fi
cd "$WT"
[ ! -e ./node_modules ] && [ -d "{path}/node_modules" ] && ln -sf "{path}/node_modules" ./node_modules
[ ! -e ./.env ]         && [ -f "{path}/.env" ]         && ln -sf "{path}/.env" ./.env
```

**NEVER** run `npm install` / `npm ci` inside a worktree. Missing dependencies in a worktree = real signal, not setup failure.

For the rest of the steps, "the working tree" means `$WT`.

## Step 1 — wait for Copilot's review (cap 30 min)

If `/tmp/babysit-{pr}-review-done` exists, skip to Step 3.

```bash
START=$(date +%s)
until [ "$(gh api repos/{ghRepo}/pulls/{pr}/reviews 2>/dev/null | jq '[.[]|select(.user.login=="copilot-pull-request-reviewer[bot]")]|length' 2>/dev/null)" -gt 0 ]; do
  if [ $(( $(date +%s) - START )) -gt 1800 ]; then echo "TIMEOUT"; exit 1; fi
  sleep 60
done
echo "REVIEW_FOUND"
```

Run as `Bash run_in_background`; poll with `BashOutput`. On TIMEOUT, write `{"phase":"review-wait","blocker":"copilot review never arrived in 30 min"}` to status and skip to Step 3 (gates can still run).

## Step 2 — handle Copilot comments

```bash
gh api repos/{ghRepo}/pulls/{pr}/comments \
  | jq '[.[] | select(.user.login=="copilot-pull-request-reviewer[bot]") | {id, node_id, path, line, body, in_reply_to_id}]' \
  > /tmp/babysit-{pr}-comments.json
```

For each top-level comment (skip ones with non-null `in_reply_to_id`):

a) `Read` the referenced file/line.
b) Judge validity per the repo's `CLAUDE.md` PR-Workflow conventions (loaded automatically since you're in `{path}`). Copilot is often wrong on context-dependent items.
c) **If valid**: implement the fix. After all valid fixes, run `{gateCmd}` (with the lock dance from Step 3 if applicable). If green, commit + push:
   ```bash
   git add -A && git commit -m "fix: address Copilot review on PR #{pr}" && git push
   ```
   Capture the commit hash.
d) **Reply** to the thread:
   ```bash
   gh api -X POST repos/{ghRepo}/pulls/{pr}/comments/<id>/replies \
     -f body='<commit hash + 1-line rationale OR clear non-applying reason>'
   ```
e) **Resolve** the thread:
   ```bash
   gh api graphql -f query='mutation{resolveReviewThread(input:{threadId:"<node_id>"}){thread{id}}}'
   ```

After all comments handled:
```bash
touch /tmp/babysit-{pr}-review-done
echo '{"pr":{pr},"phase":"review-done","applied":[...],"declined":N}' > /tmp/babysit-{pr}-status.json
```

## Step 3 — quality gate

If the repo map says this repo's gate holds a shared resource (e.g. `be-test-db`), acquire its lock:

```bash
START=$(date +%s)
until mkdir /tmp/babysit-tests-{resource}.lock 2>/dev/null; do
  if [ $(( $(date +%s) - START )) -gt 3600 ]; then echo "GATE_LOCK_TIMEOUT"; exit 1; fi
  sleep 30
done
trap 'rm -rf /tmp/babysit-tests-{resource}.lock' EXIT
```

Run `{gateCmd}` from `$WT`. Classify failures:

- **Resource collision** (DB wiped mid-run, "duplicate key on startup") → re-acquire lock, retry once.
- **Your own change in Step 2 broke it** → fix, commit, push, retry. Hard cap 3 fix attempts.
- **Pre-existing breakage on the branch** → write blocker, skip Step 4.

Release lock immediately after green (`rm -rf /tmp/babysit-tests-{resource}.lock; trap - EXIT`). Always run gates at least once.

## Step 4 — e2e suite (FE only, serialized)

**Skip entirely if `{hasE2E}` is `false`.**

The e2e harness boots an ephemeral docker stack on host ports 3100/4100 — only one PR's suite can run at a time on this machine.

```bash
START=$(date +%s)
until mkdir /tmp/babysit-e2e-stack.lock 2>/dev/null; do
  if [ $(( $(date +%s) - START )) -gt 14400 ]; then
    echo '{"pr":{pr},"phase":"step4","blocker":"e2e-stack lock wait timed out after 4h"}' > /tmp/babysit-{pr}-status.json
    exit 0
  fi
  sleep 30
done
echo "$$" > /tmp/babysit-e2e-stack.lock/owner-pid
trap 'rm -rf /tmp/babysit-e2e-stack.lock' EXIT
```

Run `{e2eCmd}` from `$WT`. The wrapper boots its own stack, seeds, runs the suite, tears down. No need to touch the user's dev servers.

On failure:
- **Spec failure looks like a real bug in PR-touched code** → read the failing spec + the source it covers, implement the obvious fix, commit `fix: <one-line> — found via e2e on PR #{pr}`, push, re-run the affected spec via `npx playwright test <spec>` inside the worktree. Hard cap 3 attempts per failing spec, the 3rd must be a *different* fix.
- **Spec failure looks like flakiness / infra** (port already bound, mongo connection refused on first try) → tear down (`docker compose -f docker-compose.test.yml down -v`), re-run `{e2eCmd}` once.
- **Pre-existing failing spec on the branch** → write blocker `"e2e failing pre-existing on {branch}: <spec name>"` and continue.

After green, release the lock immediately:
```bash
rm -rf /tmp/babysit-e2e-stack.lock; trap - EXIT
touch /tmp/babysit-{pr}-tested
```

## Step 5 — completion

```bash
touch /tmp/babysit-{pr}-done
```

If `PushNotification` was loaded, fire once:

```
PushNotification(
  title="babysit-prs",
  message="{ghRepo} #{pr} — READY ✅"   # or "BLOCKED ⚠ <one-sentence reason>"
)
```

Keep the message under 120 chars.

## Step 5.5 — prune worktree

```bash
cd /tmp
git -C {path} worktree remove --force "{path}--babysit-pr-{pr}" 2>/dev/null || true
```

If remove fails (uncommitted experimental changes), add a blocker note `"worktree at <path> kept due to local-only changes"` — don't force.

## Step 6 — return ONE JSON line

```json
{"pr": {pr}, "status": "READY|BLOCKED", "applied": ["sha", ...], "declined": N, "e2e": "X/Y or skipped", "blockers": ["reasons", ...]}
```

`READY` requires: (1) all Copilot threads replied + resolved, (2) gates green, (3) e2e green or N/A. Otherwise `BLOCKED`.

---

## Stop conditions

- **5-hour rate-limit guard.** On any 429 / "rate limit" / "usage limit" error, write blocker and exit cleanly.
- 4 hours wall-clock with no marker advancing → blocker, exit.
- Same individual operation fails 3× with 3 different recovery strategies → blocker for that item only, continue.
- Copilot comment requires a product decision → reply saying so, leave unresolved, add to blockers, don't resolve.

## Failure classification

**AUTO-FIX — implement, push, retry:**

| Symptom | Action |
|---|---|
| Test failures with collisions / fixtures wiped mid-run | Resource lock dance, retry once. |
| Lint / typecheck / build error from your own Step 2 commit | Fix, commit, push, re-run. |
| e2e spec finds a real bug in PR-touched code | Fix per Step 4 (cap 3 attempts). |
| Transient gh / git / docker network blip | Wait 10s, retry once. |

**REPORT BLOCKER — do NOT touch:**

| Symptom | Blocker line |
|---|---|
| `Cannot find module './vendor-chunks/*.js'` | `"stale .next in <repo> — run 'rm -rf <repo>/.next'"` |
| Docker daemon not running | `"docker daemon down — please start Docker"` |
| Host port 3100 or 4100 already bound by user's dev | `"port 3100/4100 in use — stop competing process and re-invoke"` |
| Database schema out of sync | `"DB schema mismatch — needs migration, manual review"` |
| Copilot comment needs design / product decision | `"PR #{pr} thread <url>: needs your call — <one-line summary>"` |
| Fix would expand scope (cross-cutting refactor, dep upgrade, schema migration, > ~5 files) | `"out of scope — suggest follow-up PR for <what>"` |

### KEY DISTINCTION

You own: code under `$WT`, gh API, git, your background processes, the ephemeral docker stack you boot.
User owns: their host dev servers, build caches (`.next`, `dist`), DB schemas, the docker daemon itself.

---

## Token-economy notes (calling session perspective)

- N background dispatches in one message, ~2KB each.
- Each subagent returns ONE JSON line (~250 chars).
- All gh / git / file work happens inside subagent contexts.
- Marker files in `/tmp/` provide resume. Wipe: `rm /tmp/babysit-*`.

## Notification extension integration

If a Claude Code notification extension is installed (e.g. `dimokol.claude-notifications`), each per-PR completion fires `PushNotification`. The extension treats each subagent's `session_id` as a distinct stage, so N PRs → N completion banners, no dedup. Token cost: ~80 tokens per PR.

If no extension is installed: no banners, workflow unaffected, results still land in the parent session via JSON returns.

## When to use vs not

**Use when:** 1+ open PRs need Copilot-review handling and/or e2e verification taken to merge-ready.
**Don't use when:** PR has no Copilot review AND no e2e coverage applicable — there's nothing to babysit. Run `{gateCmd}` directly.
