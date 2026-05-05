---
name: verify-manual-tests
description: Automate the `## Manual Testing` checkboxes of a PR by driving the running dev servers via Playwright MCP. Flips a checkbox to `[x]` only once the behavior is actually verified, and for failures either fixes the bug and pushes (then checks) or leaves it unchecked with an explanation. The only edit to the PR body is the checkbox flip — no evidence tables, screenshot links, or "verified on" footers. Use when asked to "verify manual tests", "run PR manual tests", "check off the boxes", "auto-test the PR", or right after a PR with a Manual Testing section is created / updated.
---

# verify-manual-tests

Turn `## Manual Testing` checkboxes into a verified pass. Each `- [ ]` is executed inline via Playwright — no subagents. Boxes flip to `- [x]` only on confirmed pass.

## Execution model

Run **everything inline** in the current session — no subagent delegation. Subagents add cold-start overhead, double tool initialization, and communication latency that outweigh any context savings for browser testing.

**Never run PRs in parallel** — Playwright is a shared singleton; concurrent browser sessions corrupt each other's state. Process multiple PRs sequentially.

---

## Step 1 — Preflight (parallel)

Check all servers simultaneously:

```bash
curl -sS http://localhost:4000/health & \
curl -sS -o /dev/null -w "fe:%{http_code}\n" http://localhost:3000 & \
curl -sS -o /dev/null -w "client:%{http_code}\n" http://localhost:3001 & \
wait
```

If any server is down, tell the user and stop — do not auto-start servers.

Confirm Playwright is responsive by navigating to `about:blank`.

---

## Step 2 — Fetch PR data

```bash
gh pr view <N> --repo <repo> --json body,title -q '{title: .title, body: .body}'
```

Parse all `- [ ]` lines under `## Manual Testing`. These are your work items.

**Read the diff only if** a checkbox is too terse to navigate to without it (e.g., "test the fix" with no page or action named). If all checkboxes name a concrete page or behavior, skip the diff entirely.

```bash
# Only when needed:
gh pr diff <N> --repo <repo>
```

---

## Step 3 — Auth check

Navigate to the admin FE root. If you land on a protected page (not redirected to login), you are already authenticated — proceed directly to test navigation. Do **not** re-login.

If redirected to login, use the OTP pattern:

```bash
# 1. Submit the login email via browser
# 2. Fetch the OTP:
node --env-file=/Users/dimokol/Documents/Flarmio/Projects/ridebly/ridebly-be/.env -e "
const { MongoClient } = require('mongodb');
const c = new MongoClient(process.env.DB_URL);
c.connect().then(async () => {
  const u = await c.db().collection('users').findOne(
    {email:'dimokritos.kolitsos@flarmio.com'}, {projection:{login:1}}
  );
  console.log(u?.login?.code);
  c.close();
});"
```

---

## Step 4 — Execute checkboxes

**Skip every line that is already `- [x]`.** Re-running the skill must be idempotent — only `- [ ]` items get touched.

For each unchecked item, in order:

1. **Navigate** to the relevant page/feature.
2. **Perform** the described behavior.
3. **Assert — pick the cheapest tool that proves the outcome**:
   - Checkbox names exact text/state ("toast says X", "button label = Y", "URL contains /foo") → `browser_evaluate` with a one-liner that returns a bool. Way cheaper than a full snapshot.
   - Checkbox is structural ("the dialog opens with these three sections") → `browser_snapshot` (a11y tree).
   - Never request a snapshot when an `evaluate` would do.
4. **On failure**, capture the post-mortem trio in this order — no extra tool calls beyond these three:
   - `browser_console_messages` (filter to errors + warnings — surfaces the silent JS error a snapshot misses)
   - `browser_network_requests` (filter to 4xx/5xx and to requests against your own API — catches "the click landed but the mutation 401'd")
   - `browser_take_screenshot` to `<project>/.playwright-mcp/pr<N>/fail-<slug>.png`
5. Record pass / fail / blocked in memory for the body update.

**Default timeout: 5_000 ms** for `browser_wait_for` unless the checkbox itself implies longer (e.g. "after the report generates" — use 30_000ms then). If it doesn't resolve, mark the item failed with "element/condition never appeared in 5s" and move on.

**Browser session reuse**: do NOT close/reopen the browser between checkboxes. Auth, cookies, and selected business persist — exploit them.

### Bug-fix loop — when to fix vs report

The job isn't to *catalogue* failures — it's to take this PR to merge-ready. If a checkbox fails because of a real bug, **fix it** (within scope) and re-run. If a checkbox fails because of state the user owns (build cache, dev server they started, etc.), **report a precise one-line recovery command** and move on.

**AUTO-FIX, then re-run the failing checkbox** (max 3 attempts per checkbox, escalating):

| Failure | Fix |
|---|---|
| Real bug in PR-touched code (e.g. dialog doesn't load saved state, raw enum shown instead of formatted label) | Read the relevant file, implement the obvious fix, run repo's quality gates, commit (`fix: <one-line> — found via PR #N manual test`), push, re-run the checkbox |
| Lint / typecheck error from your fix | Read the error, fix it, re-run gates |
| Missing test data | Use the Step-5 3-tier seed protocol |
| Empty selector / element not yet rendered | Increase the `wait_for` timeout for that one assertion (cap 30_000ms), retry once |

**Scope guard**: only modify files that are part of the PR's diff OR are obviously the source of the bug (a 1-file fix is always in scope; a refactor across 5 files is not). If the fix would require touching code outside the PR's surface, leave the checkbox unflipped and report.

**ESCALATE — report blocker, do not fix** (leave checkbox `- [ ]`, include in final report):

| Failure | Blocker line |
|---|---|
| `Cannot find module './vendor-chunks/*.js'` (Next.js stale cache) | "Stale `.next` for `<repo>` — run `rm -rf <repo>/.next` and restart the dev server, then re-invoke" |
| Dev server returns HTML 502 / connection refused | "Dev server for `<repo>` (port `<n>`) is down — please start `npm run dev`" |
| GraphQL query / mutation error referencing fields not in current schema | "Backend types stale — run `npm run types:update` in `<repo>`" |
| Bug requires a design / product decision (e.g. "should X cascade-delete Y?") | "Needs your call: <what + why>" |
| Fix would expand scope beyond this PR (cross-cutting refactor, dependency upgrade, schema migration) | "Out of scope for this PR: <what>; suggest follow-up PR" |
| Same operation has failed 3× with 3 different fix attempts | "Persistent: <symptom>, tried <attempts>" |

**Hard cap**: 3 fix attempts per checkbox. The 3rd attempt MUST be different from the first two (don't re-try the same fix). If the 3rd fails, escalate.

---

## Step 5 — Seed data (when needed)

When a checkbox needs prerequisite data that doesn't exist (e.g. "open a rental reservation" but there are zero reservations), follow this **3-tier fallback with a hard 2-minute effort cap**:

**Tier 1 — Reuse existing data.** Search the relevant collection / page for *any* row that satisfies the checkbox's prerequisites (right business, right status, right date window). If you find one, use it.

**Tier 2 — Seed via the admin UI.** This also exercises the creation path, which is a real bonus. Use the same Playwright session — auth and selected business are already there. Mark every UI-seeded entity with a `TEST-` prefix in the title/notes field so it's discoverable.

**Tier 3 — Direct DB seed script.** Only when the UI seed path is itself broken or too long (e.g. needs 8 form steps for one prerequisite). Write a one-off `seed-<feature>.mjs` + `cleanup-<feature>.mjs` in `/tmp/`, run them, delete both immediately after the relevant checkboxes finish. Tag rows with `TEST-<feature>-<timestamp>`.

**The 2-minute rule**: if you've spent two minutes wallclock trying to seed the data and it isn't working, mark the dependent checkbox as **blocked** ("could not seed: <reason>") and move on. Better to leave one box honestly unflipped than to thrash the whole run.

**Cleanup**: at the very end of the run, after Step 6 commits the body, run any cleanup-*.mjs scripts you wrote, then delete them. Do not leave seed scripts on disk.

**Never seed production** without explicit user confirmation. The DEV/TEST DB rule from the project CLAUDE.md applies.

---

## Step 6 — Update PR body (single write)

After all items are tested:

```bash
gh pr view <N> --repo <repo> --json body -q '.body' > /tmp/pr<N>.md
```

Edit `/tmp/pr<N>.md` — flip **only** the checkbox lines that passed (`- [ ]` → `- [x]`). No other edits: no footers, no tables, no timestamps, no evidence sections.

```bash
gh pr edit <N> --repo <repo> --body-file /tmp/pr<N>.md
```

One fetch, one write. Do not loop `gh pr edit` per checkbox.

---

## Step 7 — Report

Tell the user:

- **X/Y passed**
- For each failure: one bullet — what you asserted, what you observed, suspected cause, single next action
- If a fix is small and obvious, propose it and ask before applying — never apply silently
- If it's a confirmed bug: fix it, commit with a message referencing the failing checkbox, push, then re-run that checkbox only

---

## Rules summary

| Rule | Detail |
|------|--------|
| No subagents | Run inline always |
| No parallel PRs | Sequential only |
| Skip `[x]` boxes | Idempotent re-runs |
| Cheapest assertion wins | `browser_evaluate` for known strings; `browser_snapshot` only for structural assertions |
| Screenshot for fail | `<project>/.playwright-mcp/pr<N>/` only — never on pass |
| Failure capture trio | `console_messages` + `network_requests` + screenshot |
| Default `wait_for` timeout | 5_000 ms |
| Browser session | Reused across checkboxes — never close/reopen |
| PR body | Checkbox flips only — nothing else |
| Diff | Skip unless checkboxes are ambiguous |
| Auth | Check once; skip if already logged in |
| PR body write | One fetch → batch edits → one write |
| Seed data | 3-tier fallback (reuse / UI / DB script), 2-min effort cap |
| Bug-fix retry | Max 1 retry per checkbox after a fix |
| Cleanup | Delete `/tmp/seed-*.mjs` and `/tmp/cleanup-*.mjs` after the run |

## Token-economy notes

- Full `browser_snapshot` returns can run 5–50 KB of context. Prefer `browser_evaluate('document.body.innerText.includes("Saved")')` style checks when the assertion is a string match.
- `browser_console_messages` and `browser_network_requests` are huge by default — always filter them (errors only / 4xx-5xx only) before logging.
- The fail-trio is FIXED to 3 tool calls. Don't add more "for context" — the screenshot already captures visible state.
- Resist the urge to re-snapshot after every tiny interaction. Snapshot at the assertion point only.
