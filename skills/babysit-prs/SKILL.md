---
name: babysit-prs
description: End-to-end PR finalization for one or more open GitHub PRs. Spawns one background subagent per PR; each subagent applies the configured code reviewer's findings (and, with --double-review, also self-reviews the diff against the project's CLAUDE.md in parallel and merges both), waits on CI for the quality gate, and — for repos that declare a local e2e suite — runs it (only when the diff needs it) inside an isolated git worktree serialized by a filesystem lock. Optionally (when configured) it asks the reviewer to review in a chat tool, re-requests approval after fixes, and merges each PR into its own base branch once it is fully production-ready. Returns control to the calling session immediately. Use when the user lists 1+ PRs and asks to "babysit", "finalize", "ready for merge", "handle reviews and tests", "auto-handle PRs", or similar end-to-end PR closeout phrasing.
---

# babysit-prs

Take a list of open PRs from ready-for-review toward merge-ready — and, if your project enables auto-merge, all the way to merged — autonomously. The calling session stays usable; N short-running background subagents do the work.

## Invocation

`/babysit-prs <pr-spec> [<pr-spec> ...] [--no-merge] [--double-review]`

Each `<pr-spec>` is either:
- `<repo-key>:<pr-number>` — e.g. `be:188`
- A full GitHub PR URL — e.g. `https://github.com/<owner>/<repo>/pull/188`
- A bare PR number — only allowed when ALL specs in the list are bare and the user clarifies which repo

**Flags:**
- `--no-merge` — take every PR to fully-ready but STOP before merging; report `READY` and hand back. Only meaningful when the project config enables auto-merge (otherwise babysit never merges and this is the default behavior).
- `--double-review` — also run a dedicated self-review agent **in parallel with the reviewer** on every PR and merge both reviews. Default (no flag) = **the configured reviewer is the sole reviewer**; the self-review then runs ONLY as a fallback when the reviewer can't be reached or never reviews within the time caps, so a PR held for manual merge still got the mechanical backwards-compat / slim-shape checks.

## Configuration (provided by the project's CLAUDE.md)

The calling session reads its config from the project's `CLAUDE.md`. **Adopters:** copy `templates/CLAUDE.md-additions.md` from this repo into your project's `CLAUDE.md` and fill in your values. See `skills/babysit-prs/PRECONDITIONS.md` for a worked example.

### Repo map

| Key | Path | GitHub repo | Base branch | Gate verification | Has local e2e suite? | E2E command |
|-----|------|-------------|-------------|-------------------|----------------------|-------------|
| `<key>` | `<absolute path>` | `<owner>/<repo>` | `<base-branch>` | `<how to verify CI>` | `true`/`false` | `<cmd>` or N/A |

`<key>` is a short alias (e.g. `be`, `fe`, `api`, `web`) used in the invocation `/babysit-prs <key>:<pr>`.

### Reviewer (configurable)

- **`Reviewer GitHub login`** — the account whose PR review + approval babysit collects (e.g. `copilot-pull-request-reviewer` for GitHub Copilot, or a custom reviewer bot/human login). Babysit filters reviews/threads by this login. If unset, default to `copilot-pull-request-reviewer`.
- **`Ask reviewer via chat`** (optional) — if the reviewer must be *pinged* to review (e.g. an agent that lives in Slack/Discord/Teams rather than auto-triggering on PR open), configure the chat tool + channel/thread here. When set, the parent sends ONE message per batch asking the reviewer to review every PR on GitHub and approve there. When unset, babysit assumes the reviewer auto-reviews on PR open (the Copilot model) and just polls for it.
- **`Auto-merge`** (optional, default **off**) — when **on**, babysit merges each PR into its own base branch once it is fully production-ready (gates green, reviewer approved, no unresolved `[CRITICAL]`, prerequisites merged). When **off**, babysit stops at `READY` and hands back for a human to merge. `--no-merge` forces off for one run.

**Trust the CI, don't re-run locally.** Lint, typecheck, build, and unit tests should already run in CI on every push. Re-running them locally during babysitting is duplicate work — it costs minutes per PR, conflicts with the user's running dev servers, leaks subprocesses, and produces no new information. **Use `gh pr checks <pr> --watch` to wait for CI and read the conclusion.** Only re-run a check locally when CI itself is broken and the user asks for triage.

**Local e2e is the one exception** — when a repo has e2e tests NOT in CI, this skill runs them locally per Step 3, and only when the diff genuinely needs it (see the e2e-necessity gate). Affected-only is the default; full runs only for sweeping changes.

## Procedure (calling session)

1. **Parse + normalize** the PR list to `{key, ghRepo, path, baseBranch, hasE2E, e2eCmd, pr, branch}`. `baseBranch` comes from the CLAUDE.md repo map; `branch` is queried from `gh pr view`. Resolve `{reviewer}`, `{askConfigured}`, `{autoMerge}` from config; `{noMerge}` from the flag.

2. **Validate + filter:**
   ```bash
   gh pr view <pr> --repo <ghRepo> --json state,headRefName -q '{state,head:.headRefName}'
   ```
   Skip PRs that are not `OPEN`. Skip any PR for which `/tmp/babysit-<pr>-done` exists. **Re-check `state` immediately before any merge** — PRs can merge or close out from under a stale list.

3. **Clean stale locks:**
   ```bash
   for lock in /tmp/babysit-e2e-stack.lock /tmp/babysit-tests-*.lock; do
     [ -d "$lock" ] && rm -rf "$lock" 2>/dev/null
   done
   ```
   Use `rm -rf`, not `rmdir` — the lock dir is non-empty by design (the holder writes `owner-pid` inside), so `rmdir` silently no-ops and stale locks persist into the new session.

4. **Ask the reviewer — ONE message, only if `Ask reviewer via chat` is configured.** Post a single message via the configured chat tool listing every PR (repo + number + URL + one-line what-it-is) and instruct the reviewer to review each on its GitHub PR with inline findings and **approve on GitHub** when satisfied. Capture the chat thread reference + send time; pass both to every subagent as `{chatThread}` and `{askedAt}` (any reviewer review/approval older than `{askedAt}` is stale). If the chat tool is unavailable, do NOT abort: fall back to polling-only (subagents still run all steps) and note `"reviewer-chat unreachable"` in each PR's blockers — those PRs then can't auto-merge (no approval signal you triggered) and end `READY`.
   - **Skip this step entirely when `Ask reviewer via chat` is unset** — the reviewer auto-triggers (Copilot model); subagents just poll for it in Step 4.

5. **Dispatch one background `general-purpose` Agent per remaining PR**, passing the Per-PR task block verbatim with placeholders substituted (including `{reviewer}`, `{chatThread}`, `{askedAt}`, `{autoMerge}`, `{noMerge}`, `{doubleReview}`). Use `run_in_background: true`. Send all dispatches in a single message.

6. **Hand control back to the user.** One sentence: "Dispatched N agents in worktrees under `<path>--babysit-pr-<pr>`. Status lands in `/tmp/babysit-<pr>-status.json`. Continue with other work — I won't poll."

7. **On each subagent completion notification — verify, don't trust.**
   - Read `/tmp/babysit-{pr}-done` and the final status file.
   - If the agent's `<result>` is `API Error: ...` or any non-JSON string, OR the result text says "tests still running" / "will wait for monitor signal" / "will retry", treat the agent as **crashed** — re-dispatch the same per-PR task once. Past incident: 3 separate completion notifications for the same agent ID, each a different non-JSON message, while the actual gate result was elsewhere.
   - If the result is a parseable JSON line with `status:READY`/`MERGED`, also sanity-check it by reading `/tmp/babysit-{pr}-diff.txt` (PR's actual changed files) and the status file's recorded test-run count. "0 affected tests" on a PR that touches `test/**` files in the diff is a false-green — re-dispatch with an explicit `git fetch origin <baseBranch>` reminder.
   - Only treat `READY`/`MERGED` as real when the diff was non-empty AND either (a) affected tests > 0 and exit 0, or (b) zero source/test files changed (docs/copy-only PR).
   - **Re-count the reviewer's unresolved threads independently.** Re-run the Step-4 GraphQL query (unresolved threads authored by `{reviewer}`) from the parent and confirm `status.applied + status.declined ≥ count`. A mismatch means the subagent missed threads — re-dispatch with a note `"thread count mismatch (saw N, processed M) — filter bug or new threads landed mid-run"`. Past incident: a PR had one unresolved reviewer thread, the subagent's REST filter matched zero, the agent reported READY with `applied: 0`, and the user caught it manually. The independent recount makes any future filter regression visible.
   - **If a subagent reports `MERGED`, confirm the reviewer actually approved.** Re-query `reviewDecision` + the latest `{reviewer}` review state. A merge without an `APPROVED` review newer than `{askedAt}` is a procedure violation (the merge gate should make it impossible).
   - Reap leaked subprocesses owned by the dead agent: `ps -ef | grep -E 'jest|cross-env|node.*--watch' | grep -v 'Visual Studio\|Discord'` — kill PIDs whose start time is within the dispatch window AND parent isn't a user-owned watcher. The `trap '... EXIT'` cleanup in subagent prompts does NOT fire when the runtime kills the subagent externally.
   - **Release leaked e2e-stack lock.** Same root cause — when the runtime reaps a subagent after it returns its JSON line, the in-prompt `trap 'rm -rf /tmp/babysit-e2e-stack.lock' EXIT` doesn't fire, and the next e2e agent blocks on the 4-hour lock-wait for nothing. Check via:
     ```bash
     if [ -d /tmp/babysit-e2e-stack.lock ]; then
       PID=$(cat /tmp/babysit-e2e-stack.lock/owner-pid 2>/dev/null)
       if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
         rm -rf /tmp/babysit-e2e-stack.lock
       fi
     fi
     ```
     `kill -0 <pid>` only checks "is this PID alive" — it doesn't signal the process.

8. **Merge any `READY_HELD` PRs in dependency order (auto-merge only).** A subagent marks its PR `READY_HELD` (approved + green but NOT merged) when a declared prerequisite — a paired/blocking PR, possibly in another repo — hadn't merged when the subagent hit its merge gate. Subagents run in parallel and must never merge out of order, so the parent resolves ordering after they return:
   - Build the dependency graph from each PR's declared prerequisites (PR-body `Paired with` / `depends on #N` / blocker notes in the status files). A `Paired with` PR is a prerequisite only when *this* PR depends on it — judge direction from the diff.
   - Merge in topological order: a held PR merges only once every prerequisite shows `state: MERGED`. Immediately before each merge, re-verify `gh pr view <pr> --repo <ghRepo> --json mergeable,mergeStateStatus,reviewDecision` (`reviewDecision == APPROVED`), then `gh pr merge <pr> --repo <ghRepo> --merge` into its own base.
   - **Skip when `--no-merge` or auto-merge is off.** If a cycle or unmet external prerequisite remains, report `"#X held: prerequisite #Y not merged"` — never merge out of declared order.

9. **After all subagents/merges settle** (or on user request), prune leftover worktrees and locks:
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

> Substitute `{pr}`, `{ghRepo}`, `{path}`, `{baseBranch}`, `{hasE2E}` (`true`/`false`), `{e2eCmd}`, `{branch}`, `{reviewer}` (reviewer GitHub login), `{chatThread}` (reviewer chat thread, or empty), `{askedAt}` (epoch seconds, or 0), `{autoMerge}` (`true`/`false`), `{noMerge}` (`true`/`false`), `{doubleReview}` (`true`/`false`).

You are a PR babysitter for ONE pull request. Take it from "ready-for-review" to "merge-ready" (and to **merged** when auto-merge is on and `{noMerge}` is false), then return ONE JSON status line.

**PR:** {pr} on {ghRepo}, branch `{branch}`, working tree at `{path}`.
**Reviewer:** GitHub login `{reviewer}`. When `{doubleReview}` is `true` you also self-review in parallel (Step 1) and merge the reviewer's findings with yours (Step 4); when it is `false` (default) the configured reviewer is the sole reviewer and Step 1 runs only as a fallback if the reviewer can't be reached. Any reviewer review/approval older than `{askedAt}` is stale; ignore it. If the reviewer replies in a chat tool (`{chatThread}` set), read the **thread** (e.g. Slack `conversations_replies` on `{chatThread}`) — channel-history endpoints typically return ONLY top-level messages, so they show the reviewer's last *root* post (an old date) and make them look inactive while they reply in-thread. Authoritative review/approval is GitHub (`reviewDecision`), not chat.
**Gate verification:** GitHub CI (`gh pr checks {pr} --repo {ghRepo} --watch`). Do NOT run lint/build/typecheck/unit-tests locally — CI already does it on every push.
**Local e2e suite:** {hasE2E} ({e2eCmd} when true). Runs locally because there's no CI for it — and only when the diff needs it (Step 3).

## NON-NEGOTIABLE RULES

1. **Execute. Do not narrate.** Every sentence that isn't a tool call wastes tokens.
2. **Block on background processes before returning.** If you run a long command via `Bash run_in_background`, you MUST poll `BashOutput` (or use `Monitor`) in a loop until the shell exits, THEN inspect the result, THEN proceed. Returning a JSON line — or any "tests still running, will wait for signal" message — while a background process you started is alive is a procedure violation. The runtime does NOT keep your agent alive between turns; if you return early, your background work is orphaned. Past incident: an agent returned "Tests still running" with `tool_uses: 18` and the bash subprocess continued for another 10 min, leaking a unit-test chain and a dev server.
3. **Ground analysis in the actual diff.** Before claiming "the PR adds file X" or "test Y is affected", run `git diff --name-only origin/{baseBranch}...HEAD` and read the output. Don't invent file names from the branch name or PR title — past incident: an agent invented a "PR-introduced spec" when the actual diff was 8 unrelated files.
4. **Load `PushNotification` once at start** via `ToolSearch query="select:PushNotification" max_results=1`. If unavailable, skip the notification step — do not abort.
5. **Never invoke another subagent.** You are the leaf.
6. **Status file is your truth source.** Update `/tmp/babysit-{pr}-status.json` after **every meaningful action**, not just phase transitions. Granular status enables resume after a crash. A status file stuck at `phase:start` with 8 tool calls already executed is a bug, not a checkpoint.
7. **No `--no-verify`, no `--amend`.** Every fix is a new commit.

## Step 0 — initialize

```
ToolSearch query="select:PushNotification" max_results=1
```

```bash
echo '{"pr":{pr},"phase":"start"}' > /tmp/babysit-{pr}-status.json
[ -f /tmp/babysit-{pr}-done ] && { echo '{"pr":{pr},"status":"already-done"}'; exit 0; }

# Disk gate — block when host disk is too tight for a Docker harness.
# Past incident: 3 e2e babysitters dispatched in parallel each spawned a Docker
# stack; collectively hit ENOSPC mid-build, leaving stale locks + uncommitted
# spec fixes in force-removed worktrees. Catch this BEFORE starting work.
FREE_GB=$(df -g / 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "$FREE_GB" ] && [ "$FREE_GB" -lt 10 ]; then
  echo '{"pr":{pr},"status":"BLOCKED","blockers":["host disk <10GB free ('"$FREE_GB"'GB) — refusing to start to avoid ENOSPC mid-Docker-build; prune buildx + worktrees first"]}' \
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

# Crash-safe worktree cleanup. The Step 7.5 prune is the happy path; this trap
# is the failure-mode safety net — the runtime CAN kill subagents externally
# (rate limits, ENOSPC, timeouts), and without the trap the worktree leaks with
# uncommitted edits invisible inside it.
trap 'cd /tmp; git -C "{path}" worktree remove --force "'"$WT"'" 2>/dev/null; git -C "{path}" worktree prune 2>/dev/null' EXIT
```

**NEVER** run `npm install` / `npm ci` inside a worktree. Missing dependencies in a worktree = real signal, not setup failure.

For the rest of the steps, "the working tree" means `$WT`.

## Step 0.6 — fetch base + verify diff

```bash
git fetch origin {baseBranch} 2>&1 | tail -3
git diff --name-only origin/{baseBranch}...HEAD > /tmp/babysit-{pr}-diff.txt
test -s /tmp/babysit-{pr}-diff.txt || { echo "EMPTY_DIFF: branch has no commits ahead of origin/{baseBranch}"; exit 1; }
echo "PR-changed files:"; cat /tmp/babysit-{pr}-diff.txt
```

**Why this exists:** affected-only test runners (`--changedSince` / `--only-changed`) compare against `origin/{baseBranch}`. If the worktree's ref is stale, the diff is empty and "0 affected tests" is reported as gate-passed — a false-green. The fetch + diff dump fixes this and gives subsequent steps a ground-truth file list. If the diff is empty, write blocker `"branch has no commits ahead of origin/{baseBranch} — already merged or wrong branch"` and exit.

## Step 1 — self-review (only with `--double-review`, or as reviewer-unreachable fallback)

**When to run this step:**
- **`{doubleReview}` is `true`** → run it NOW, in parallel with the reviewer's review, so the PR is never blocked on one reviewer; Step 4 merges the reviewer's findings with these.
- **`{doubleReview}` is `false` (default)** → **SKIP this step here**; the configured reviewer is the sole reviewer. Run it later ONLY as a fallback if the reviewer turns out unreachable or never reviews within the Step 4/5 caps (Step 4b redirects here), so a PR held for manual merge still gets the mechanical checks below.

**Why these checks matter whenever they run:** self-review is fast, deterministic, and catches design / safety / parity / convention drift CI can't — especially the cross-repo backwards-compat grep and the slim-shape consumer audit, which a prose review routinely misses.

If `/tmp/babysit-{pr}-self-reviewed` exists, skip this step.

a) **Load context.** Read the project `CLAUDE.md` (at `{path}/CLAUDE.md`) and the diff (`/tmp/babysit-{pr}-diff.txt`). For each changed source file, `Read` it.

b) **Review against:**
   - Project conventions from CLAUDE.md.
   - Generic correctness — null/undefined risk, race conditions, leaked promises, dead code, missing error handling at system boundaries.
   - Test parity — if the diff touches product behavior, are the relevant specs updated?
   - **Cross-repo backwards-compat (`[CRITICAL]` if violated).** If the diff deletes or renames any GraphQL field/type, model field, enum value, REST route, or exported function, `git grep` each removed identifier against the base branches of every OTHER repo in the Repo map (plus `main` if different). Any hit = real BC break → `[CRITICAL]`, regardless of paired-PR claims. The agent typically loads CLAUDE.md + diff but never greps cross-repo, so renames slip through as `[SUGGESTION]` when they are really BC violations. Past incident: a backend PR renamed 4 fields on a slim type, self-review called it `[SUGGESTION]`, and the paired frontend's protected branch still queried the old names — would have errored production on first deploy.
     ```bash
     for repo_path in <other repo paths from Repo map>; do
       git -C "$repo_path" fetch origin {baseBranch} main 2>/dev/null
       git -C "$repo_path" grep -nE "\\b<id>\\b" origin/{baseBranch} origin/main -- '<paths-likely-to-consume-this>' || true
     done
     ```
   - **Slim-shape consumer audit (`[WARNING]` min, `[CRITICAL]` if a safety/correctness check).** If the diff introduces a slim/projection type, replaces a "full" type with a slim one, or narrows a `select`, grep every consumer for each field present in the OLD shape but absent in the new one. Missing field → silent regression. Past incident: a slim-shape migration silently dropped 4 used fields, including one that disabled a compliance safety warning.

c) **Produce findings** with the `[CRITICAL]` / `[WARNING]` / `[SUGGESTION]` taxonomy (data-loss/security/regression vs correctness/maintainability vs perf/cleanup).

d) **Post as ONE top-level PR comment:**
   ```bash
   gh pr comment {pr} --repo {ghRepo} --body "$(cat <<'EOF'
   ## Self-review

   Reviewed the diff against project CLAUDE.md, generic correctness, cross-repo backwards-compat, and test parity.

   ### [CRITICAL]
   - `path/to/file:line` — issue + suggested fix
   ### [WARNING]
   - ...
   ### [SUGGESTION]
   - ...
   EOF
   )"
   ```
   If nothing worth flagging after a genuine read, post `"## Self-review\n\nReviewed the diff against CLAUDE.md. No findings."` — audit trail. Never silently skip the posting.

e) **Implement `[CRITICAL]` and `[WARNING]` items.** One commit per logical fix:
   ```bash
   git add -A && git commit -m "fix: address self-review on PR #{pr} — <one-line>" && git push
   ```

f) **For `[SUGGESTION]` items — default to fixing them in THIS PR.** Fold anything deferrable into this PR rather than punting it. Defer ONLY when the item is a big expansion (cross-cutting refactor, dep upgrade, schema migration, > ~5 files) or could plausibly break the existing fix. When you do defer, note it in the step-(g) reply and in a `deferred[]` array in your status JSON.

g) **Reply** to your self-review comment with a follow-up (applied / declined) via `gh api -X POST repos/{ghRepo}/issues/{pr}/comments`.

h) **Status + marker:**
   ```bash
   echo '{"pr":{pr},"phase":"self-reviewed","self_review_applied":<N>,"self_review_declined":<M>}' > /tmp/babysit-{pr}-status.json
   touch /tmp/babysit-{pr}-self-reviewed
   ```

**Gate:** any `[CRITICAL]` you could not auto-fix MUST appear in `blockers[]` (Step 8) and makes the PR non-mergeable.

## Step 2 — quality gate (GitHub CI)

```bash
gh pr checks {pr} --repo {ghRepo} --watch --required 2>&1 | tee /tmp/babysit-{pr}-ci.log
GH_EXIT=${PIPESTATUS[0]}
```

Classify:
- **All green** → continue to Step 3.
- **Your own Step 1 commit broke a check** → `gh run view <run-id> --log-failed`, fix, commit, push, re-watch. Hard cap 3 fix attempts.
- **Pre-existing failure unrelated to PR diff** (failure log references files NOT in the diff) → blocker `"CI failing pre-existing on {branch}: <check> — <cause>"`. Don't fix.
- **CI infra failure** (timeout / runner unavailable / transient 5xx) → `gh run rerun <run-id> --failed`, wait once more.

**Do NOT re-run lint/build/typecheck/unit-tests locally to "double check" CI.**

## Step 3 — local e2e suite (only repos with `hasE2E: true`, serialized)

**Skip entirely if `{hasE2E}` is `false`.**

**Police e2e hard — boot the harness only when the diff needs it.** The Docker stack is the most expensive thing babysit does, so skip it whenever you safely can:
1. **No behavioral surface in the diff** → if `/tmp/babysit-{pr}-diff.txt` is only non-behavioral files (copy/translation, docs, comments, config, generated types, test-only changes already run by CI), skip with `"e2e":"skipped-no-behavioral-change"`. Don't boot a stack to confirm a string changed.
2. **Behavioral change present** → run `{e2eCmd}` (affected-only). Default; almost always right.
3. **Full suite** → ONLY for sweeping changes plausibly affecting most specs (shared layout/provider, auth, global config, a dep bump touching many files). Never default to full.

The e2e harness boots its own ephemeral stack (auto-selected host ports recommended — see `e2e-harness-patterns` skill). Only one PR's suite runs at a time (serialized by the babysit lock):

```bash
START=$(date +%s)
until mkdir /tmp/babysit-e2e-stack.lock 2>/dev/null; do
  if [ $(( $(date +%s) - START )) -gt 14400 ]; then
    echo '{"pr":{pr},"phase":"e2e","blocker":"e2e-stack lock wait timed out after 4h"}' > /tmp/babysit-{pr}-status.json
    exit 0
  fi
  sleep 30
done
echo "$$" > /tmp/babysit-e2e-stack.lock/owner-pid
trap 'rm -rf /tmp/babysit-e2e-stack.lock' EXIT
```

```bash
E2E_PRUNE_ON_EXIT=1 {e2eCmd}
```

On failure:
- **Spec failure looks like a real bug in PR-touched code** → fix, commit `fix: <one-line> — found via e2e on PR #{pr}`, push, re-run the affected spec. Hard cap 3 attempts per spec; the 3rd must be a *different* fix.
- **Flakiness / infra** (DB connection refused, container healthcheck timeout) → tear down per the project's documented teardown, re-run `{e2eCmd}` once.
- **Pre-existing failing spec on the branch** → blocker `"e2e failing pre-existing on {branch}: <spec>"`, continue.

After green, release the lock:
```bash
rm -rf /tmp/babysit-e2e-stack.lock; trap - EXIT
touch /tmp/babysit-{pr}-tested
```

## Step 4 — reviewer pickup

By now CI (Step 2), e2e (Step 3), and — if `{doubleReview}` was set — self-review (Step 1) have run, so the reviewer ({reviewer}) has had several minutes to review (whether auto-triggered or asked in Step 4 of the parent). Collect the review, merge with your self-review, apply what's valid.

If `/tmp/babysit-{pr}-review-done` exists, skip this step.

a) **Re-query the reviewer's reviews + inline threads in ONE call:**
```bash
OWNER="${ghRepo%/*}"; NAME="${ghRepo#*/}"
gh api graphql -F owner="$OWNER" -F name="$NAME" -F pr={pr} -f query='
  query($owner:String!,$name:String!,$pr:Int!){
    repository(owner:$owner,name:$name){
      pullRequest(number:$pr){
        reviews(first:20){ nodes{ author{login} state body submittedAt } }
        reviewThreads(first:50){
          nodes{ id isResolved comments(first:20){ nodes{ databaseId author{login} path body createdAt replyTo{databaseId} } } }
        }
      }
    }
  }' > /tmp/babysit-{pr}-review.json

REV_COUNT=$(jq --arg r "{reviewer}" '[.data.repository.pullRequest.reviews.nodes[]|select(.author.login==$r)]|length' /tmp/babysit-{pr}-review.json)
THREAD_COUNT=$(jq --arg r "{reviewer}" '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved|not)|select(.comments.nodes[0].author.login==$r)]|length' /tmp/babysit-{pr}-review.json)
echo "reviewer: $REV_COUNT reviews, $THREAD_COUNT unresolved threads"
```

**Why GraphQL, not REST:** GraphQL returns each thread `id` (`PRRT_*`) needed by `resolveReviewThread`, and filters on one consistent login in a single round-trip. Some reviewers (notably GitHub Copilot) surface under three different REST logins (`Copilot`, `copilot-pull-request-reviewer`, `copilot-pull-request-reviewer[bot]`) depending on API surface — a REST filter that matched only one once reported `applied: 0` while a real comment was unhandled. One known login via GraphQL avoids that class of bug.

b) **If no review yet (`$REV_COUNT == 0` AND `$THREAD_COUNT == 0`):** first, **if you have not already self-reviewed (i.e. `{doubleReview}` was `false`), run the Step 1 self-review NOW as the fallback** — post findings, apply `[CRITICAL]`/`[WARNING]` fixes, push — so a held PR still got the mechanical checks. Then:
   - If `{chatThread}` is set (you asked the reviewer): poll the query every 60s for up to ~15 min; at ~5 min still nothing, post ONE reply in `{chatThread}` bumping the PR; at the cap, blocker `"awaiting reviewer review"`, touch the marker, continue (the PR will end `READY`, never merged).
   - If `{chatThread}` is empty (auto-trigger model): the reviewer may have errored/never run. Treat the fallback self-review as the sole signal, touch the marker, and continue.

c) **If a reviewer review body exists, treat it like your self-review** — apply `[CRITICAL]`/`[WARNING]` as commits, fold in `[SUGGESTION]` per Step 1(f), reply with applied/declined. The reviewer can be wrong on context-dependent items — judge each against CLAUDE.md.

d) **If `$THREAD_COUNT > 0`, handle each unresolved reviewer thread:**
```bash
jq --arg r "{reviewer}" '[.data.repository.pullRequest.reviewThreads.nodes[]
   | select(.isResolved|not) | . as $t | $t.comments.nodes[0]
   | select(.author.login==$r) | { threadId: $t.id, commentId: .databaseId, path, body }]' \
  /tmp/babysit-{pr}-review.json > /tmp/babysit-{pr}-comments.json
```
For each item: `Read` the file; judge validity per CLAUDE.md; if valid implement + commit + push; **reply** via `gh api -X POST repos/{ghRepo}/pulls/{pr}/comments/<commentId>/replies -f body='...'` (REST required — no GraphQL reply); **resolve** via `gh api graphql -f query='mutation{resolveReviewThread(input:{threadId:"<threadId>"}){thread{id isResolved}}}'`.

e) **If you applied fixes, CI re-runs.** Re-watch (Step 2 logic, cap 3). If fixes touched behavioral surface, re-run e2e per Step 3 policing.

f) **Status:**
```bash
touch /tmp/babysit-{pr}-review-done
echo '{"pr":{pr},"phase":"review-handled","reviewer_threads":'"$THREAD_COUNT"',"applied":[...],"declined":N,"deferred":[...]}' > /tmp/babysit-{pr}-status.json
```

## Step 5 — request approval (auto-merge only)

**Skip this step if `{autoMerge}` is false or `{noMerge}` is true** — go to Step 8 and report `READY`.

A PR can't auto-merge without the reviewer's approval (`{reviewer}`, review state `APPROVED`, newer than your last commit).

```bash
gh pr view {pr} --repo {ghRepo} --json reviewDecision,reviews \
  -q '{decision:.reviewDecision, rev:([.reviews[]|select(.author.login=="{reviewer}")]|sort_by(.submittedAt)|last)}'
LAST_COMMIT_TS=$(git log -1 --format=%cI)
```

- **Approved AND newer than your last commit** → go to Step 6.
- **Not approved, or approved before your latest fix** → if `{chatThread}` is set, post ONE reply asking the reviewer to re-review + approve; poll `reviewDecision` every 60s up to ~15 min.
  - **APPROVED** (newer than `LAST_COMMIT_TS`) → Step 6.
  - **CHANGES_REQUESTED / new threads** → loop back to Step 4 (cap 3 review rounds; an unresolved 3rd round → blocker `"reviewer still requesting changes after 3 rounds — needs your call"`).
  - **No response at the cap, or no chat configured to ask** → blocker `"awaiting reviewer approval"`; PR ends `READY` (held), never auto-merged.
- **Edge — PR authored by `{reviewer}`** → the reviewer can't approve its own PR → blocker `"PR authored by the reviewer — needs another approver"`. Don't merge.

## Step 6 — merge gate (auto-merge only)

**Skip if `{autoMerge}` is false or `{noMerge}` is true** — report `READY`.

Confirm "fully production-ready" — ALL must hold: **if a self-review was performed** (`--double-review` or the reviewer-unreachable fallback) it's posted + every `[CRITICAL]`/`[WARNING]` applied or justified + no unresolved `[CRITICAL]`; CI green; e2e green / skipped-verified / skipped-no-behavioral-change; every reviewer thread replied + resolved; reviewer `APPROVED` newer than the last commit (`reviewDecision == APPROVED`); `blockers[]` empty. If any fails → don't merge; report `READY` (held) or `BLOCKED`.

**Prerequisites:** read the PR body for declared prerequisites (`Paired with <repo>: PR #N`, `depends on #N`) — possibly in another repo. A `Paired with` PR is a prerequisite only when *this* PR depends on it (judge direction). For each true prerequisite, check `gh pr view <N> --repo <prereqRepo> --json state`:
- **All `MERGED`** → safe to merge.
- **Any still open** → return `READY_HELD` with `held_on: ["<repo>#N", ...]`; the parent (its Step 8) merges held PRs in dependency order. Never merge ahead of a declared prerequisite.

Merge into the PR's own base — nothing else:
```bash
BASE=$(gh pr view {pr} --repo {ghRepo} --json baseRefName -q '.baseRefName')
gh pr merge {pr} --repo {ghRepo} --merge   # into $BASE; use --squash if the repo disallows merge commits; NEVER change the base
```
Do NOT promote one branch to another (e.g. `dev`→`main`) — that's a separate, deliberate step the user owns. On a clean merge, record `"status":"MERGED","merged_into":"'"$BASE"'"`. On failure (conflict / base moved), do NOT force; conflict → blocker `"merge conflict with <base> — needs manual resolution"` (resolution must preserve both sides; never `--theirs`/`--ours`).

## Step 7 — completion

```bash
touch /tmp/babysit-{pr}-done
```

If `PushNotification` was loaded, fire once (≤120 chars):
```
PushNotification(title="babysit-prs", message="{ghRepo} #{pr} — MERGED ✅")  # or "READY ✅" / "READY_HELD ⏳ <prereq>" / "BLOCKED ⚠ <reason>"
```

## Step 7.5 — prune worktree

```bash
cd /tmp
git -C {path} worktree remove --force "{path}--babysit-pr-{pr}" 2>/dev/null || true
```
If remove fails (uncommitted experimental changes), add blocker `"worktree at <path> kept due to local-only changes"` — don't force.

## Step 8 — return ONE JSON line

```json
{"pr": {pr}, "status": "MERGED|READY|READY_HELD|BLOCKED", "merged_into": "<base>|null", "reviewer_approved": true, "applied": ["sha", ...], "declined": N, "deferred": ["..."], "e2e": "X/Y | skipped-already-verified | skipped-no-behavioral-change | N/A", "held_on": ["repo#N", ...], "blockers": ["reasons", ...]}
```

- **`MERGED`** — auto-merge on, all gates held, reviewer approved, prerequisites merged, `gh pr merge` succeeded into the base.
- **`READY`** — gates green + (reviewer approved or auto-merge off / `--no-merge`); handed back for a human to merge. Also used when the reviewer never reviewed/approved — with the fallback self-review run when `--double-review` was off (`blockers` says why).
- **`READY_HELD`** — fully approved + green, NOT merged only because a declared prerequisite (`held_on`) hasn't merged yet.
- **`BLOCKED`** — an unresolved `[CRITICAL]`, a red gate, a merge conflict, or any `blockers[]` item. Never merged.

**Branch protection (`reviewDecision: REVIEW_REQUIRED`)** is satisfied by the reviewer's approval, not by a babysit comment. With auto-merge off, the PR ends `READY` and the human approves + merges.

---

## Stop conditions

- **Rate-limit guard.** On any 429 / "rate limit" / "usage limit" error, write blocker and exit cleanly.
- 4 hours wall-clock with no marker advancing → blocker, exit.
- Same individual operation fails 3× with 3 different recovery strategies → blocker for that item only, continue.
- Reviewer comment requires a product decision → reply saying so, leave unresolved, add to blockers, don't resolve.
- Reviewer unreachable / no review or approval within the Step 4/5 caps → PR ends `READY` (held), never auto-merged. Not a hard failure.

## Failure classification

**AUTO-FIX — implement, push, retry:**

| Symptom | Action |
|---|---|
| CI failure caused by your own Step 1 commit | `gh run view <id> --log-failed`, fix, commit, push, re-watch. |
| e2e spec finds a real bug in PR-touched code | Fix per Step 3 (cap 3 attempts). |
| Transient gh / git / docker network blip | Wait 10s, retry once. |
| CI runner timeout / infra 5xx | `gh run rerun <id> --failed`, re-watch once. |

**REPORT BLOCKER — do NOT touch:**

| Symptom | Blocker line |
|---|---|
| Stale build cache breaks a local run | `"stale build cache in <repo> — clear it"` |
| Docker daemon not running | `"docker daemon down — please start Docker"` |
| CI failing on a check unrelated to PR diff | `"CI <check> failing pre-existing — see <run url>"` |
| `gh pr checks` returns `no checks reported` | wait 30s, retry once; if still none, `"no CI configured for this branch — gate cannot be verified"` |
| Database schema out of sync | `"DB schema mismatch — needs migration, manual review"` |
| Reviewer comment needs design / product decision | `"PR #{pr} thread <url>: needs your call — <summary>"` |
| Fix would expand scope (cross-cutting refactor, dep upgrade, schema migration, > ~5 files) | `"out of scope — suggest follow-up PR for <what>"` |

### KEY DISTINCTION

You own: code under `$WT`, gh API, git, the ephemeral docker stack the e2e wrapper boots (Step 3 only).
User owns: their host dev servers, build caches, DB schemas, the docker daemon itself.

**Never spawn a competing server.** If a port the user's dev environment binds is in use, that's user state — flag as blocker, don't kill, don't bind elsewhere to "get around it".

Marker files in `/tmp/babysit-*` provide resume across crashes. Wipe to force a fresh run: `rm /tmp/babysit-*`.
