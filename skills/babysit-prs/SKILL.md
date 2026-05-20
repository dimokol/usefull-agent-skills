---
name: babysit-prs
description: End-to-end PR finalization for one or more open GitHub PRs. Spawns one background subagent per PR; each subagent independently handles Copilot review (parallel across PRs) — falling back to an inline self-review of the diff against the project's CLAUDE.md when Copilot fails (timeout / errored / fluff-only) — waits on CI for the quality gate, and — for repos that declare a local e2e suite — runs it inside an isolated git worktree (serialized by a filesystem lock to limit concurrent resource usage). Returns control to the calling session immediately. Use when the user lists 1+ PRs and asks to "babysit", "finalize", "ready for merge", "handle reviews and tests", "auto-handle PRs", or similar end-to-end PR closeout phrasing.
---

# babysit-prs

Take a list of open PRs to merge-ready autonomously. The calling session stays usable — N short-running background subagents do the actual work.

## Invocation

`/babysit-prs <pr-spec> [<pr-spec> ...]`

Each `<pr-spec>` is either:
- `<repo-key>:<pr-number>` — e.g. `be:188`
- A full GitHub PR URL — e.g. `https://github.com/<owner>/<repo>/pull/188`
- A bare PR number — only allowed when ALL specs in the list are bare and the user clarifies which repo

## Repo map (provided by the project's CLAUDE.md)

The calling session reads its repo map from the project's `CLAUDE.md`. The map declares one row per repo this skill should babysit:

| Key | Path | GitHub repo | Base branch | Gate verification | Has local e2e suite? | E2E command |
|-----|------|-------------|-------------|-------------------|----------------------|-------------|
| `<key>` | `<absolute path>` | `<owner>/<repo>` | `<base-branch>` | `<how to verify CI>` | `true`/`false` | `<cmd>` or N/A |

`<key>` is a short alias (e.g. `be`, `fe`, `api`, `web`) used in the invocation `/babysit-prs <key>:<pr>`.

**Adopters:** copy `templates/CLAUDE.md-additions.md` from this repo into your project's `CLAUDE.md` and fill in your own values. See `skills/babysit-prs/PRECONDITIONS.md` for a worked example and what your project needs to have wired up.

**Trust the CI, don't re-run locally.** Lint, typecheck, build, and unit tests should already run in CI on every push. Re-running them locally during babysitting is duplicate work — it costs minutes per PR, conflicts with the user's running dev servers, leaks subprocesses, and produces no new information. **Use `gh pr checks <pr> --watch` to wait for CI and read the conclusion.** Only re-run a check locally when CI itself is broken (red status) and the user asks for triage.

**Local e2e is the one exception** — when a repo has e2e tests that are NOT in CI (intentional cost or stack-isolation decision), this skill runs them locally per Step 4. The CLAUDE.md repo map flags which repos this applies to via `Has local e2e suite? = true`. Affected-only is the default; fall back to a full run only when the affected runner reports "no specs matched" while the diff clearly impacts product behavior, or when the user asks.

## Procedure (calling session)

1. **Parse + normalize** the PR list to `{key, ghRepo, path, baseBranch, hasE2E, e2eCmd, pr, branch}`. `baseBranch` comes from the CLAUDE.md repo map; `branch` is queried from `gh pr view`.

2. **Validate + filter:**
   ```bash
   gh pr view <pr> --repo <ghRepo> --json state,headRefName -q '{state,head:.headRefName}'
   ```
   Skip PRs that are not `OPEN`. Skip any PR for which `/tmp/babysit-<pr>-done` exists.

3. **Clean stale locks:**
   ```bash
   for lock in /tmp/babysit-e2e-stack.lock /tmp/babysit-tests-*.lock; do
     [ -d "$lock" ] && rm -rf "$lock" 2>/dev/null
   done
   ```
   Use `rm -rf`, not `rmdir` — the lock dir is non-empty by design (the holder writes `owner-pid` inside), so `rmdir` silently no-ops and stale locks persist into the new session.

4. **Dispatch one background `general-purpose` Agent per remaining PR**, passing the Per-PR task block verbatim with placeholders substituted. Use `run_in_background: true`. Send all dispatches in a single message.

5. **Hand control back to the user.** One sentence: "Dispatched N agents in worktrees under `<path>--babysit-pr-<pr>`. Status lands in `/tmp/babysit-<pr>-status.json`. Continue with other work — I won't poll."

6. **On each subagent completion notification — verify, don't trust.**
   - Read `/tmp/babysit-{pr}-done` and the final status file.
   - If the agent's `<result>` is `API Error: ...` or any non-JSON string, OR the result text says "tests still running" / "will wait for monitor signal" / "will retry", treat the agent as **crashed** — re-dispatch the same per-PR task once. Past incident: 3 separate completion notifications for the same BE agent ID, each with a different non-JSON message, while the actual gate result was elsewhere.
   - If the result is a parseable JSON line with `status:READY`, also sanity-check it by reading `/tmp/babysit-{pr}-diff.txt` (PR's actual changed files) and the status file's recorded test-run count. "0 affected tests" on a PR that touches `test/**` files in the diff is a false-green — re-dispatch with an explicit `git fetch origin dev` reminder.
   - Only treat `READY` as truly ready when the diff was non-empty AND either (a) affected tests > 0 and exit 0, or (b) zero source/test files changed (docs/copy-only PR).
   - **Re-count Copilot threads independently.** Re-run the Step-2 GraphQL query (unresolved Copilot threads) from the parent and confirm `status.applied + status.declined ≥ count`. A mismatch means the subagent missed threads — re-dispatch with a note `"thread count mismatch (saw N, processed M) — filter bug or new threads landed mid-run"`. Past incident: PR #289 had one unresolved Copilot thread, the subagent's REST filter matched zero, agent reported READY with `applied: 0`, and the user caught it manually. The independent recount makes any future filter regression visible.
   - Reap leaked subprocesses owned by the dead agent: `ps -ef | grep -E 'jest|cross-env|node.*--watch' | grep -v 'Visual Studio\|Discord'` — kill PIDs whose start time is within the dispatch window AND parent isn't a user-owned watcher (started before the babysit dispatch). The `trap '... EXIT'` cleanup in subagent prompts does NOT fire when the runtime kills the subagent externally.
   - **Release leaked e2e-stack lock.** Same root cause as the leaked-subprocess case — when the runtime reaps a subagent after it returns its JSON line, the in-prompt `trap 'rm -rf /tmp/babysit-e2e-stack.lock' EXIT` doesn't fire. The next FE agent in line would then block on the 4-hour lock-wait timeout for nothing. Past incident: an e2e-suite subagent returned READY, was reaped before its trap could clean up, left the lock owned by a dead PID — the next agent in the queue would have blocked indefinitely. Check via:
     ```bash
     if [ -d /tmp/babysit-e2e-stack.lock ]; then
       PID=$(cat /tmp/babysit-e2e-stack.lock/owner-pid 2>/dev/null)
       if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
         rm -rf /tmp/babysit-e2e-stack.lock
       fi
     fi
     ```
     The `kill -0 <pid>` only checks "is this PID alive" — it doesn't signal the process.

7. **After all subagents return** (or on user request), prune leftover worktrees and locks:
   ```bash
   for path in <each touched repo>; do
     git -C "$path" worktree prune
   done
   for lock in /tmp/babysit-e2e-stack.lock /tmp/babysit-tests-*.lock; do
     [ -d "$lock" ] && rm -rf "$lock" 2>/dev/null
   done
   ```

The calling session never modifies the user's main checkouts — every subagent works in its own worktree.

---

## Per-PR subagent task (passed verbatim with placeholders substituted)

> Substitute `{pr}`, `{ghRepo}`, `{path}`, `{baseBranch}`, `{hasE2E}` (`true`/`false`), `{e2eCmd}`, `{branch}`.
> `{baseBranch}` is the repo's default merge target (e.g. `main`, `dev`, `develop`) — pulled from the CLAUDE.md repo map.
> `{branch}` is the PR's head branch.

You are a PR babysitter for ONE pull request. Take it from "open with potentially-pending Copilot review" to "merge-ready", then return ONE JSON status line.

**PR:** {pr} on {ghRepo}, branch `{branch}`, working tree at `{path}`.
**Gate verification:** GitHub CI (`gh pr checks {pr} --repo {ghRepo} --watch`). Do NOT run lint/build/typecheck/jest locally — CI already does it on every push.
**Local e2e suite:** {hasE2E} ({e2eCmd} when true). Runs locally because there's no CI for it (or the project chose local-only).

## NON-NEGOTIABLE RULES

1. **Execute. Do not narrate.** Every sentence that isn't a tool call wastes tokens.
2. **Block on background processes before returning.** If you run a long command via `Bash run_in_background`, you MUST poll `BashOutput` (or use `Monitor`) in a loop until the shell exits, THEN inspect the result, THEN proceed. Returning a JSON line — or any "tests still running, will wait for signal" message — while a background process you started is alive is a procedure violation. The runtime does NOT keep your agent alive between turns; if you return early, your background work is orphaned. Past incident: an agent returned "Tests still running" with `tool_uses: 18` and the bash subprocess continued running for another 10 min, leaking a `npm run jest` chain and a dev server.
3. **Ground analysis in the actual diff.** Before claiming "the PR adds file X" or "test Y is affected", run `git diff --name-only origin/{baseBranch}...HEAD` and read the output. Don't invent file names from the branch name or PR title — past incident: an agent invented `outsourceBooking.test.ts` as a "PR-introduced spec" when the actual diff was 8 unrelated booking-payment files.
4. **Load `PushNotification` once at start** via `ToolSearch query="select:PushNotification" max_results=1`. If unavailable, skip the notification step at the end — do not abort.
5. **Never invoke another subagent.** You are the leaf.
6. **Status file is your truth source.** Update `/tmp/babysit-{pr}-status.json` after **every meaningful action**, not just phase transitions — after fetching base, after fetching comments, after each comment processed (record the resolved thread id), before starting tests, after tests exit. Granular status enables resume after a crash. A status file stuck at `phase:start` with 8 tool calls already executed is a bug, not a checkpoint.
7. **No `--no-verify`, no `--amend`.** Every fix is a new commit.

## Step 0 — initialize

```
ToolSearch query="select:PushNotification" max_results=1
```

```bash
echo '{"pr":{pr},"phase":"start"}' > /tmp/babysit-{pr}-status.json
[ -f /tmp/babysit-{pr}-done ] && { echo '{"pr":{pr},"status":"already-done"}'; exit 0; }

# Disk gate — block dispatch when host disk is too tight for a Docker harness.
# Past incident (2026-05-15): 3 FE babysitters dispatched in parallel each
# spawned a Docker stack; collectively hit ENOSPC mid-build, leaving stale
# locks + uncommitted spec fixes in force-removed worktrees. Catch this BEFORE
# starting work, not as a buildx error 10 minutes in.
FREE_GB=$(df -g / 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "$FREE_GB" ] && [ "$FREE_GB" -lt 10 ]; then
  echo '{"pr":{pr},"status":"BLOCKED","blockers":["host disk <10GB free ('"$FREE_GB"'GB) — refusing to start to avoid ENOSPC mid-Docker-build; run docker buildx prune + worktree cleanup first"]}' \
    | tee /tmp/babysit-{pr}-status.json
  exit 0
fi
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

# Crash-safe worktree cleanup. The Step 5.5 prune is the happy path; this trap
# is the failure-mode safety net. The runtime CAN kill subagents externally
# (rate limits, ENOSPC, timeouts) — without the trap the worktree leaks and
# any uncommitted edits inside survive but stay invisible. Past incident
# (2026-05-15): an ENOSPC-killed agent left two babysit worktrees behind; the
# manual cleanup force-removed them, losing an uncommitted spec fix. With the
# trap, we'd have at least committed-and-pushed before force-remove.
trap 'cd /tmp; git -C "{path}" worktree remove --force "'"$WT"'" 2>/dev/null; git -C "{path}" worktree prune 2>/dev/null' EXIT
```

**NEVER** run `npm install` / `npm ci` inside a worktree. Missing dependencies in a worktree = real signal, not setup failure.

For the rest of the steps, "the working tree" means `$WT`.

## Step 0.6 — fetch base + verify diff

```bash
git fetch origin dev 2>&1 | tail -3
git diff --name-only origin/{baseBranch}...HEAD > /tmp/babysit-{pr}-diff.txt
test -s /tmp/babysit-{pr}-diff.txt || { echo "EMPTY_DIFF: branch has no commits ahead of origin/{baseBranch}"; exit 1; }
echo "PR-changed files:"; cat /tmp/babysit-{pr}-diff.txt
```

**Why this exists:** affected-only test runners (`jest --changedSince=origin/{baseBranch}`, `playwright --only-changed`) compare against `origin/{baseBranch}`. If the worktree's `origin/{baseBranch}` ref is stale, the diff is empty and "0 affected tests" is reported as gate-passed — a false-green. Past incident: a BE PR with 8 changed files (incl. 2 modified test files) reported "0 affected tests" because the worktree never fetched. The fetch + diff dump fixes this and gives subsequent steps a ground-truth file list.

If the diff is empty, that's a real signal — write blocker `"branch has no commits ahead of origin/{baseBranch} — already merged or wrong branch"` and exit. Don't run gates on a no-op diff.

## Step 1 — wait for Copilot's review (cap 10 min)

If `/tmp/babysit-{pr}-review-done` exists, skip to Step 3.

**Fast-fail upfront check — run this FIRST, synchronously (not in background):**

```bash
OWNER="${ghRepo%/*}"; NAME="${ghRepo#*/}"

# How many Copilot reviews exist right now?
COPILOT_COUNT=$(gh api graphql -F owner="$OWNER" -F name="$NAME" -F pr={pr} -f query='
  query($owner:String!,$name:String!,$pr:Int!){
    repository(owner:$owner,name:$name){
      pullRequest(number:$pr){
        reviews(first:10){
          nodes{ author{ login } state submittedAt }
        }
        createdAt
      }
    }
  }' 2>/dev/null \
  | jq '
    .data.repository.pullRequest
    | {
        count: (.reviews.nodes | map(select(.author.login | test("copilot"; "i"))) | length),
        ageSeconds: (now - (.createdAt | fromdateiso8601) | floor)
      }
  ' 2>/dev/null)

COUNT=$(echo "$COPILOT_COUNT" | jq -r '.count // 0')
AGE=$(echo "$COPILOT_COUNT"  | jq -r '.ageSeconds // 0')

if [ "$COUNT" -gt 0 ]; then
  echo "COPILOT_REVIEW_ALREADY_PRESENT — skip poll, proceed to Step 1.5"
  # fall through to Step 1.5 classification (may still be errored/fluff)
elif [ "$AGE" -gt 300 ]; then
  # PR is >5 min old with 0 Copilot reviews — it has already failed silently.
  # Past incident: babysit wasted 30 min polling while Copilot had already errored.
  echo "COPILOT_FAST_FAIL: PR is ${AGE}s old, 0 reviews — skipping poll"
  touch /tmp/babysit-{pr}-copilot-timeout
  # Jump directly to Step 1.5
else
  # PR is fresh — Copilot may still be processing. Poll briefly.
  START=$(date +%s)
  until [ "$(gh api graphql -F owner="$OWNER" -F name="$NAME" -F pr={pr} -f query='query($owner:String!,$name:String!,$pr:Int!){repository(owner:$owner,name:$name){pullRequest(number:$pr){reviews(first:10){nodes{author{login}}}}}}' 2>/dev/null | jq '[.data.repository.pullRequest.reviews.nodes[]|select(.author.login|test("copilot";"i"))]|length' 2>/dev/null)" -gt 0 ]; do
    if [ $(( $(date +%s) - START )) -gt 600 ]; then
      echo "TIMEOUT after 10 min"
      touch /tmp/babysit-{pr}-copilot-timeout
      break
    fi
    sleep 30
  done
fi
```

On TIMEOUT or fast-fail, write `{"phase":"review-wait","blocker":"copilot review never arrived"}` to status and proceed to Step 1.5 (do NOT skip to Step 3 — gates alone are not a review).

## Step 1.5 — Copilot failure detection + self-review fallback

**Why this step exists:** Branch-protected base branches require a review signal; treating a Copilot failure as "no review needed" is unsafe. CI catches lint/types/tests, not design / safety / parity / convention drift. When Copilot's review fails, do a self-review of the diff against the project `CLAUDE.md` and handle findings the same way you'd handle Copilot's comments. Adopters who codify their own self-review rule (in CLAUDE.md or memory) should follow that rule too.

Classify Copilot's outcome:

```bash
COPILOT_STATUS=ok
[ -f /tmp/babysit-{pr}-copilot-timeout ] && COPILOT_STATUS=timeout

if [ "$COPILOT_STATUS" = "ok" ]; then
  REVIEW_BODY=$(gh api repos/{ghRepo}/pulls/{pr}/reviews 2>/dev/null \
    | jq -r '[.[]|select(.user.login=="copilot-pull-request-reviewer[bot]")] | sort_by(.submitted_at) | last | .body // ""')

  # Errored body
  echo "$REVIEW_BODY" | grep -qiE "copilot encountered an error|unable to (review|analyze|process)|something went wrong" && COPILOT_STATUS=errored

  # Fluff-only: short body AND no structured findings (headers / bullets / line refs / inline code)
  if [ "$COPILOT_STATUS" = "ok" ]; then
    LEN=$(printf '%s' "$REVIEW_BODY" | wc -c | tr -d ' ')
    FINDINGS=$(printf '%s' "$REVIEW_BODY" | grep -cE '(^|\s)(##|\*\*|- |\* |line [0-9]|`[^`]+`)' || true)
    [ "${LEN:-0}" -lt 400 ] && [ "${FINDINGS:-0}" = "0" ] && COPILOT_STATUS=fluff
  fi
fi

echo "COPILOT_STATUS=$COPILOT_STATUS"
```

**If `$COPILOT_STATUS == ok`, skip the rest of this step — proceed to Step 2.**

Otherwise, do the self-review:

a) **Load context.** Read the project `CLAUDE.md` (at `{path}/CLAUDE.md` — you are in `$WT`) and the diff (`/tmp/babysit-{pr}-diff.txt` from Step 0.6). For each changed source file in the diff, `Read` it.

b) **Review against:**
   - Project conventions from CLAUDE.md (translations, custom-component reuse, dark mode, backwards-compat, file/folder naming, language-aware navigation, etc.).
   - Generic correctness — null/undefined risk, race conditions, leaked promises, dead code, missing error handling at system boundaries.
   - Test parity — if the diff touches product behavior, are the relevant specs updated? Use the repo's `@covers` convention (FE) or co-located test files (BE) to check.
   - **Cross-repo backwards-compat (`[CRITICAL]` if violated).** If the diff deletes or renames any GraphQL field/type, model field, enum value, REST route, or exported function, `git grep` each removed identifier against the base branches (`origin/{baseBranch}` for every OTHER repo in the Repo map, plus `origin/main` if different from `{baseBranch}`). Hits = real BC break — promote to `[CRITICAL]`. A "paired PR migrates the consumer" claim does NOT cover production state on the protected branch. The agent typically loads CLAUDE.md + diff + changed files but never greps cross-repo, so renames slip through as `[SUGGESTION]` when they are really BC violations. Past incident: a BE PR renamed 4 GraphQL fields on a slim calendar type and self-review classified it `[SUGGESTION]`; the paired FE's `main` branch still queried the old names verbatim — would have errored the production calendar on first deploy. Concrete check, per removed identifier `<id>`:
     ```bash
     for repo_path in <other repo paths from Repo map>; do
       git -C "$repo_path" fetch origin {baseBranch} main 2>/dev/null
       git -C "$repo_path" grep -nE "\\b<id>\\b" origin/{baseBranch} origin/main -- '<paths-likely-to-consume-this>' || true
     done
     ```
     Any hit = `[CRITICAL]` BC violation, regardless of paired-PR claims.
   - **Slim-shape consumer audit (`[WARNING]` minimum, `[CRITICAL]` if a safety/correctness check).** If the diff introduces a slim/projection type, replaces a "full" type with a slim one, or narrows a `select` / `projectionFromInfo`, the slim shape may silently drop fields the existing consumers render. For every field present in the OLD shape but absent in the new shape, grep all consumers (`git grep <fieldName>` across every repo in the Repo map) and verify they don't read it. Missing field → silent UI/feature regression. Past incident: an FE PR migrated to a slim calendar shape and the commit message claimed "fields the route card doesn't render"; consumer grep found 4 used fields silently dropped, including one that silently disabled a tax-compliance vehicle-mismatch safety warning. Promote a dropped safety-critical field (compliance checks, payment-status guards, permission gates) to `[CRITICAL]`.

c) **Produce findings** with the `AI_REVIEW=1` taxonomy:
   - `[CRITICAL]` — data loss, security, regression risk, broken backwards-compat
   - `[WARNING]` — correctness, maintainability, convention violation
   - `[SUGGESTION]` — perf, cleanup, naming

d) **Post as ONE top-level PR comment** (not a review — simpler to track and reply to):
   ```bash
   gh pr comment {pr} --repo {ghRepo} --body "$(cat <<'EOF'
   ## Self-review (Copilot review unavailable: <status>)

   Per project rule: when Copilot review fails, perform a self-review of the diff against project CLAUDE.md rather than merging blind.

   ### [CRITICAL]
   - `path/to/file:line` — issue + suggested fix
   - ...

   ### [WARNING]
   - ...

   ### [SUGGESTION]
   - ...
   EOF
   )"
   ```
   If you find nothing worth flagging after a genuine read, post exactly that: `"## Self-review (Copilot unavailable: <status>)\n\nReviewed the diff against CLAUDE.md. No findings."` — this is the audit trail that the self-review happened. Never silently skip the posting.

e) **Implement `[CRITICAL]` and `[WARNING]` items.** One commit per logical fix (don't bulk-bundle):
   ```bash
   git add -A && git commit -m "fix: address self-review on PR #{pr} — <one-line>" && git push
   ```

f) **For `[SUGGESTION]` items:** judge each. If cheap + clearly valuable, implement same way. Otherwise note as declined (not silently skipped — the reply in step (g) records it).

g) **Reply** to your self-review comment with a follow-up summary (applied / declined). Use `gh api -X POST repos/{ghRepo}/issues/{pr}/comments` with a body like `"Self-review follow-up: applied <N> fixes (<sha list>). Declined: <items + one-line reason each>."`.

h) **Status:**
   ```bash
   echo '{"pr":{pr},"phase":"self-reviewed","copilot_status":"'"$COPILOT_STATUS"'","self_review_applied":<N>,"self_review_declined":<M>}' > /tmp/babysit-{pr}-status.json
   ```

**Final-step gate:** Any `[CRITICAL]` finding that you could not auto-fix MUST appear in `blockers[]` in Step 6. A PR with an unresolved `[CRITICAL]` from self-review is `BLOCKED`, not `READY`.

## Step 2 — handle Copilot comments

Fetch comments **and** their thread IDs in one GraphQL call. Split `{ghRepo}` into `<owner>/<name>` first:

```bash
OWNER="${ghRepo%/*}"; NAME="${ghRepo#*/}"
gh api graphql -F owner="$OWNER" -F name="$NAME" -F pr={pr} -f query='
  query($owner:String!,$name:String!,$pr:Int!){
    repository(owner:$owner,name:$name){
      pullRequest(number:$pr){
        reviewThreads(first:50){
          nodes{
            id isResolved
            comments(first:20){
              nodes{
                databaseId
                author{login}
                path
                body
                replyTo{databaseId}
              }
            }
          }
        }
      }
    }
  }' \
  | jq '[.data.repository.pullRequest.reviewThreads.nodes[]
         | select(.isResolved | not)
         | . as $t
         | $t.comments.nodes[0]
         | select(.author.login == "copilot-pull-request-reviewer")
         | {
             threadId: $t.id,
             commentId: .databaseId,
             path, body
           }]' \
  > /tmp/babysit-{pr}-comments.json

test "$(jq 'length' /tmp/babysit-{pr}-comments.json)" = "0" \
  && echo "WARN: 0 unresolved Copilot threads — sanity-check the raw threads below" \
  && gh api graphql -F owner="$OWNER" -F name="$NAME" -F pr={pr} -f query='query($owner:String!,$name:String!,$pr:Int!){repository(owner:$owner,name:$name){pullRequest(number:$pr){reviewThreads(first:50){nodes{isResolved comments(first:1){nodes{author{login} path}}}}}}}'
```

**Why GraphQL, not REST:** The REST `/pulls/<n>/comments` endpoint returns Copilot's inline comments under three different `user.login` values across PRs and repos (`Copilot`, `copilot-pull-request-reviewer`, `copilot-pull-request-reviewer[bot]`). GraphQL uses one consistent handle: `copilot-pull-request-reviewer`. Past incident on PR #289: REST filter looked for `[bot]`, payload had `Copilot`, agent reported READY with `applied: 0` and the user caught it.

The single GraphQL call also returns the thread `id` (a `PRRT_*` node id) — exactly what `resolveReviewThread` needs in Step 2e. With REST you'd need a second round-trip to map `databaseId` → thread id.

Skip resolved threads (`isResolved == false`) so you don't re-process a thread the user already closed. Use the **first** comment of each thread (`.comments.nodes[0]`) as the "top-level" — the API returns them in chronological order.

For each item in `/tmp/babysit-{pr}-comments.json` (each is one unresolved Copilot thread):

a) `Read` the referenced file (use `path` from the JSON).
b) Judge validity per the repo's `CLAUDE.md` PR-Workflow conventions (loaded automatically since you're in `{path}`). Copilot is often wrong on context-dependent items.
c) **If valid**: implement the fix. Commit + push (let CI re-validate — no local gate run needed):
   ```bash
   git add -A && git commit -m "fix: address Copilot review on PR #{pr}" && git push
   ```
   Capture the commit hash.
d) **Reply** to the thread (uses the REST `commentId` from the JSON — there's no GraphQL `addPullRequestReviewThreadReply` for this, REST is required):
   ```bash
   gh api -X POST repos/{ghRepo}/pulls/{pr}/comments/<commentId>/replies \
     -f body='<commit hash + 1-line rationale OR clear non-applying reason>'
   ```
e) **Resolve** the thread (uses the GraphQL `threadId` from the JSON):
   ```bash
   gh api graphql -f query='mutation{resolveReviewThread(input:{threadId:"<threadId>"}){thread{id isResolved}}}'
   ```

After all comments handled:
```bash
touch /tmp/babysit-{pr}-review-done
echo '{"pr":{pr},"phase":"review-done","applied":[...],"declined":N}' > /tmp/babysit-{pr}-status.json
```

## Step 3 — quality gate (GitHub CI)

Wait for CI on the PR's HEAD SHA. `--watch` blocks until all required checks complete (no polling loop, no leaked subprocess risk).

```bash
gh pr checks {pr} --repo {ghRepo} --watch --required 2>&1 | tee /tmp/babysit-{pr}-ci.log
GH_EXIT=${PIPESTATUS[0]}
```

`gh pr checks --watch` exits 0 if all required checks pass, non-zero if any failed/cancelled. Read the log to learn which check(s) and why.

Classify:

- **All green** → continue to Step 4.
- **Your own Step 2 commit broke a check** → read `gh run view <run-id> --log-failed` for the failed check, fix, commit, push, re-run `gh pr checks --watch`. Hard cap 3 fix attempts.
- **Pre-existing failure unrelated to PR diff** (the failure log references files NOT in `/tmp/babysit-{pr}-diff.txt`) → blocker `"CI failing pre-existing on {branch}: <check name> — <one-line cause>"`. Don't try to fix.
- **CI infra failure** (timeout, runner unavailable, transient 5xx in the log) → re-run via `gh run rerun <run-id> --failed`, wait once more.

**Do NOT re-run lint/build/typecheck/jest locally to "double check" CI.**

## Step 4 — local e2e suite (only repos with `hasE2E: true`, serialized)

**Skip entirely if `{hasE2E}` is `false`.**

The e2e harness is expected to boot its own ephemeral stack (auto-selected host ports recommended — see `e2e-harness-patterns` skill, Pattern 1). Only one PR's suite can run at a time on this machine (serialized by the babysit lock to avoid resource exhaustion — Pattern 5). This step exists *only* because e2e has no CI by project decision; everything else (lint, build, typecheck, unit tests) was already covered by Step 3.

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

Run `{e2eCmd}` from `$WT` with `E2E_PRUNE_ON_EXIT=1` set so the wrapper prunes its own stack-named images + 24h+-old buildx cache on teardown. The wrapper boots its own stack, seeds, runs the suite, tears down.

```bash
E2E_PRUNE_ON_EXIT=1 {e2eCmd}
```

The prune flag is opt-in by repo convention (paid by ~3 min on next cold boot of the same worktree) — make it the default in babysit runs because the parallel-PR pattern accumulates buildx cache faster than humans notice.

On failure:
- **Spec failure looks like a real bug in PR-touched code** → read the failing spec + the source it covers, implement the obvious fix, commit `fix: <one-line> — found via e2e on PR #{pr}`, push, re-run the affected spec via `npx playwright test <spec>` inside the worktree. Hard cap 3 attempts per failing spec, the 3rd must be a *different* fix.
- **Spec failure looks like flakiness / infra** (DB connection refused on first try, container healthcheck timeout) → tear down the harness stack per the project's documented teardown command, re-run `{e2eCmd}` once.
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

`READY` requires: (1) all Copilot threads replied + resolved, (2) if Step 1.5 ran, all self-review `[CRITICAL]` and `[WARNING]` findings either applied (commit hash captured) or replied-with-justification, (3) gates green, (4) e2e green or N/A. Otherwise `BLOCKED`. An unresolved `[CRITICAL]` from self-review is a blocker regardless of how green CI is.

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
| CI lint/typecheck/build/jest failure caused by your own Step 2 commit | Read `gh run view <id> --log-failed`, fix, commit, push, re-watch. |
| e2e spec finds a real bug in PR-touched code | Fix per Step 4 (cap 3 attempts). |
| Transient gh / git / docker network blip | Wait 10s, retry once. |
| CI runner timeout / infra 5xx | `gh run rerun <id> --failed`, re-watch once. |

**REPORT BLOCKER — do NOT touch:**

| Symptom | Blocker line |
|---|---|
| `Cannot find module './vendor-chunks/*.js'` | `"stale .next in <repo> — run 'rm -rf <repo>/.next'"` |
| Docker daemon not running | `"docker daemon down — please start Docker"` |
| CI failing on a check unrelated to PR diff | `"CI <check> failing pre-existing — see <run url>"`. Don't try to debug; user decides. |
| `gh pr checks` returns `no checks reported` | PR pushed but CI hasn't started yet — wait 30s and retry once. If still none, blocker `"no CI configured for this branch — gate cannot be verified"`. |
| Database schema out of sync | `"DB schema mismatch — needs migration, manual review"` |
| Copilot comment needs design / product decision | `"PR #{pr} thread <url>: needs your call — <one-line summary>"` |
| Fix would expand scope (cross-cutting refactor, dep upgrade, schema migration, > ~5 files) | `"out of scope — suggest follow-up PR for <what>"` |

### KEY DISTINCTION

You own: code under `$WT`, gh API, git, the ephemeral docker stack the FE e2e wrapper boots (Step 4 only).
User owns: their host dev servers (whatever ports they run on), build caches (`.next`, `dist`), DB schemas, the docker daemon itself.

**Never spawn a competing server.** If a port that the user's dev environment binds is already in use, that's user state — flag as blocker, don't kill, don't bind to an alternate port to "get around it".

Marker files in `/tmp/babysit-*` provide resume across crashes. Wipe to force a fresh run: `rm /tmp/babysit-*`.
