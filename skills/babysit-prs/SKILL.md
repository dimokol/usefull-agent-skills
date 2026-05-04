---
name: babysit-prs
description: End-to-end PR finalization for one or more open PRs. Spawns a single background orchestrator that handles Copilot review (parallel across PRs, auto-implements valid suggestions, replies + resolves every thread per the repo's CLAUDE.md), then runs verify-manual-tests sequentially (Playwright is single-instance), and finishes only when every listed PR is merge-ready. Returns control immediately so the user can keep working. Use when the user lists 2+ PRs and asks to "babysit", "finalize", "ready for merge", "handle reviews and tests", "auto-handle PRs", or similar end-to-end PR closeout phrasing.
---

# babysit-prs

Take a list of open PRs to merge-ready autonomously. Main session stays cheap — one background orchestrator does everything else.

## Invocation

`/babysit-prs <repo>:<pr> [<repo>:<pr> ...]`

Example: `/babysit-prs be:188 fe:256 client:166`

If the user passes bare numbers, ask which repo each belongs to before proceeding. If still ambiguous, stop.

## Repo map

| Key | Path | GitHub repo |
|-----|------|-------------|
| `be` | `~/Documents/Flarmio/Projects/ridebly/ridebly-be` | `Knorcedger/ridebly-be` |
| `fe` | `~/Documents/Flarmio/Projects/ridebly/ridebly-fe` | `Knorcedger/ridebly-fe` |
| `client` | `~/Documents/Flarmio/Projects/ridebly/ridebly-client` | `Knorcedger/ridebly-client` |

Resolve once in main session, pass into the orchestrator prompt — never read repo files in the main session beyond this lookup.

## Procedure (main session)

1. **Validate** each PR with `gh pr view <pr> --repo <gh-repo> --json state,headRefName -q '{state,head:.headRefName}'`. Skip closed/merged PRs and tell the user.
2. **Skip already-finalized PRs**: if `/tmp/babysit-<pr>-tested` exists, exclude it (resume support). Mention which were skipped.
3. **Dispatch ONE background `general-purpose` Agent** with `run_in_background: true`. Its prompt is the entire `## Orchestrator plan` block below, with PR placeholders substituted.
4. **Hand control back to the user** with the orchestrator's task ID and a one-line "running in background — you'll be notified per PR completion and at the end" message. Do not do anything else.

Do NOT dispatch per-PR agents from the main session — every direct dispatch leaks its summary into your context. Delegate the fan-out to the orchestrator.

---

## Orchestrator plan (passed verbatim to the background agent)

> Substitute `<PRS>` with a JSON list `[{repo, ghRepo, path, pr, branch}, …]` from main-session resolution.

You are the PR babysitter. Take this PR list to merge-ready, then exit:

**PRs:** `<PRS>`

### Phase A — Copilot review handling (PARALLEL across PRs)

For each PR, spawn ONE `run_in_background: true` `general-purpose` subagent with this self-contained task prompt:

```
PR: {pr} on {ghRepo} (branch {branch}). Repo path: {path}.

1. WAIT for Copilot's review:
   Loop until `gh api repos/{ghRepo}/pulls/{pr}/reviews | jq '[.[]|select(.user.login=="copilot-pull-request-reviewer[bot]")]|length>0'` returns true. Between polls, use ScheduleWakeup with delaySeconds=270 (cache window). Cap total wait at 30 minutes.

2. cd into {path}. The harness will load the repo's CLAUDE.md — read its "PR Workflow" section to know the project's conventions for replying/resolving threads.

3. List Copilot comments:
   gh api repos/{ghRepo}/pulls/{pr}/comments \
     | jq '[.[] | select(.user.login=="copilot-pull-request-reviewer[bot]") | {id, node_id, path, line, body}]'

4. For each comment, decide validity per repo CLAUDE.md (use judgment — Copilot can be wrong about niche/wrong-context items):
   a) VALID → implement the fix. Run repo quality gates (be: lint+typecheck+jest; fe/client: lint+build). Commit (no --no-verify, no --amend). Push.
   b) NOT VALID → no code change.
   c) Reply via `gh api repos/{ghRepo}/pulls/{pr}/comments/{id}/replies -f body='…'` with either commit hash + 1-line rationale OR a clear non-applying reason.
   d) Resolve the thread: `gh api graphql -f query='mutation{resolveReviewThread(input:{threadId:"{node_id}"}){thread{id}}}'`.

5. Touch /tmp/babysit-{pr}-review-done.

6. Return ONE compact JSON line, nothing else:
   {"pr":{pr},"applied":[<commit hashes>],"declined":N,"blockers":[<short strings>]}
```

**Token rules for Phase A:**
- Use `run_in_background: true` always — react to completion notifications, do not poll.
- Don't ask the children for narration; they return one JSON line.
- Don't aggregate intermediate state — trust the markers + returns.

### Phase B — Manual testing (SEQUENTIAL across PRs)

After ALL Phase-A markers exist (`/tmp/babysit-<pr>-review-done` for each PR), iterate the original PR order. For each PR, INLINE (do NOT spawn a subagent — `verify-manual-tests` is already inline-optimised):

1. Invoke the `verify-manual-tests` skill with the PR's repo and number.
2. Wait for it to complete (synchronous when run inline).
3. Touch `/tmp/babysit-<pr>-tested`.

Only ONE `verify-manual-tests` runs at a time across the whole babysit run — Playwright is a singleton.

### Done criteria — a PR is merge-ready when ALL of:

1. Every Copilot review thread has a reply AND is resolved.
2. Repo quality gates green (be: lint+typecheck+test; fe/client: lint+build).
3. Every `- [ ]` in the PR body's `## Manual Testing` section is `- [x]`.
4. No unresolved blockers from Phase A or Phase B.

### Stop conditions — pause + notify IMMEDIATELY when

- **5-hour rolling token usage ≥ 90%.** Detect by:
  a) Catching any 429 / "rate limit" / "usage limit" error from any tool call. On first such error, stop spawning new work, finish current sub-tasks if cheap, then exit cleanly.
  b) Best-effort soft check at the start of each Phase: `claude /usage 2>&1 | head -20` (if the CLI exposes it). If parseable and ≥90%, exit cleanly.
  c) Conservative heuristic: never spawn Phase B if Phase A took >2.5 hours of wall clock — assume budget pressure.
- A subagent fails the same task 3× in a row.
- 4 hours wall-clock with no forward progress (no marker created in 4h).
- A blocker requires a product decision (e.g., Copilot suggests a UX change you can't decide alone).
- CI/quality gates keep failing for a non-obvious reason after 1 push attempt.

When pausing: write `/tmp/babysit-status.md` with current state per PR, then PushNotification the user with a 1-line summary + path to the status file. Do NOT delete markers — a re-invocation can resume.

### Per-PR completion notifications

After EACH PR finishes Phase B (whether READY or BLOCKED), send a PushNotification:

> `babysit-prs: <repo>:<pr> READY ✅` or
> `babysit-prs: <repo>:<pr> BLOCKED ⚠ — <one-line reason>`

### Final report (the orchestrator's single return value)

≤30 lines total, one section per PR. Format:

```
## babysit-prs report

### {repo}:{pr} — READY ✅ | BLOCKED ⚠
- Copilot: {applied} valid → applied & pushed ({hashes}); {declined} declined ({short reasons or empty})
- Manual tests: {pass}/{total} passed ({fail-slugs if any})
- Quality gates: green | failing ({which})
- Blockers: {bullets or "none"}

…

Status file: /tmp/babysit-status.md
```

### Token-budget rules (orchestrator's own context)

- **Never** read repo files in YOUR (orchestrator) context — push everything into Phase-A subagents (they `cd` into the repo and see the right CLAUDE.md).
- Phase-A subagent return values are ≤300 chars (one JSON line each). Don't aggregate them into prose during the run; only the final report parses them.
- Use `Monitor` (not Bash sleep loops) ONLY if you need to react to a continuous log stream. For one-shot waits, use `Bash run_in_background` with an `until` condition.
- Use `ScheduleWakeup 270s` for any "wait then check again" beat. Never sleep > 300s in any single hop (cache TTL).
- Don't snapshot or screenshot from this orchestrator — verify-manual-tests handles all browser interaction.

### Resume support

If `/tmp/babysit-<pr>-review-done` exists for a PR, skip Phase A for it. If `/tmp/babysit-<pr>-tested` exists, skip Phase B too.

To force a clean run, the user can `rm /tmp/babysit-*` before re-invoking.

---

## Stop & cleanup (main session, after orchestrator returns)

1. Surface the orchestrator's final report to the user (verbatim).
2. Tell them which PRs are merge-ready and which need their attention.
3. Do NOT auto-merge. Merging is always the user's call.
