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

For each unchecked item, in order:

1. **Navigate** to the relevant page/feature
2. **Perform** the described behavior
3. **Assert** with `browser_snapshot` — check the a11y/text tree for the expected outcome
4. **Screenshot only on failure** — save to `<project>/.playwright-mcp/pr<N>/fail-<slug>.png`; never on pass (saves tool calls)
5. Record pass or fail in memory for the body update

**Timeouts**: if `browser_wait_for` hasn't resolved in a reasonable time (use explicit timeout ms), mark the item as failed with "element/condition never appeared" and move on.

---

## Step 5 — Seed data (when needed)

If a checkbox needs a specific data shape that doesn't exist in the dev environment, **seed it — don't skip the item**. The dev DB is for testing; never leave a checkbox unverified just because the state is missing.

- Prefer creating test data through the UI — it tests the creation path too
- For complex state (multi-leg bookings, specific status combos, edge-case enum values): write a one-off `seed-<feature>.mjs` + `cleanup-<feature>.mjs`, run them, delete both files after testing. Mark seeded rows with a `TEST-<FEATURE>-<N>` identifier for safe cleanup
- Run the cleanup script before reporting back, so the dev DB stays clean
- After seeding, hard-refresh the page so React Query / SWR caches re-fetch the new data
- If the UI filters out the seeded state by design (e.g., calendars hide cancelled bookings, lists exclude soft-deleted rows), surface that in the final report and leave the box unchecked with a one-line reason — don't pretend a hidden state was verified
- Never seed production without explicit user confirmation

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
| Snapshot for pass | `browser_snapshot` (a11y tree) |
| Screenshot for fail | `<project>/.playwright-mcp/pr<N>/` only |
| PR body | Checkbox flips only — nothing else |
| Diff | Skip unless checkboxes are ambiguous |
| Auth | Check once; skip if already logged in |
| PR body write | One fetch → batch edits → one write |
