# useful-agent-skills

A collection of Claude Code skills for AI-assisted development workflows. Each skill is a single self-contained markdown file you drop into `~/.claude/skills/`.

---

## Install

### One-liner (recommended)

Install a specific skill:

```bash
curl -fsSL https://raw.githubusercontent.com/dimokol/usefull-agent-skills/main/install.sh | bash -s verify-manual-tests
```

Install all skills at once:

```bash
curl -fsSL https://raw.githubusercontent.com/dimokol/usefull-agent-skills/main/install.sh | bash
```

Then **restart Claude Code** (or open a new session) — skills are picked up on session start.

### Manual install

Skills are plain markdown files. Copy any skill directory to `~/.claude/skills/`:

```bash
mkdir -p ~/.claude/skills/<skill-name>
curl -fsSL https://raw.githubusercontent.com/dimokol/usefull-agent-skills/main/skills/<skill-name>/SKILL.md \
  -o ~/.claude/skills/<skill-name>/SKILL.md
```

---

## Skills

### `verify-manual-tests` &nbsp;·&nbsp; *partially reusable*

Automates the `## Manual Testing` checkboxes in a GitHub PR by driving running dev servers via Playwright MCP. Each checkbox is executed **inline** (no subagent overhead, no context-passing latency). Boxes flip to `[x]` only when the behavior is confirmed; failures are left unchecked with a clear explanation. The only edit to the PR body is the checkbox flip — no evidence tables, no timestamps, no "verified on" footers.

Highlights:
- **Idempotent** — re-runs skip every `[x]` box.
- **Cheapest assertion wins** — `browser_evaluate` for known strings, `browser_snapshot` only for structural checks. Saves 80%+ of token-payload per assertion vs always-snapshot.
- **Fixed failure-capture trio** — `console_messages` + `network_requests` + screenshot. Three calls per failure, no more.
- **Auto-seed** with a 3-tier fallback (reuse existing → UI seed → DB seed script) and a hard 2-minute effort cap to prevent thrashing.
- **Browser session reuse** across checkboxes (don't close/reopen between assertions).
- **Bug-fix retry capped at 1** per checkbox; second failure → leave unchecked + report.

**Trigger phrases:** "verify manual tests", "run PR manual tests", "check off the boxes", "auto-test PR #N"

**Requirements:**
- Claude Code with Playwright MCP enabled
- `gh` CLI authenticated
- Dev servers already running (the skill checks; it does not auto-start)
- A PR with a `## Manual Testing` section using `- [ ]` checkboxes

**To adapt to your project (the project-specific bits):**
- Update the **dev-server ports** in Step 1 (currently `4000` / `3000` / `3001`).
- Replace the **OTP / login flow** in Step 3 with whatever your auth pattern is — it currently fetches an OTP from MongoDB's `users.login.code` (Ridebly-specific).
- Update the **screenshot artifacts path** if you don't want `<project>/.playwright-mcp/`.

The general flow (preflight → fetch PR → auth → execute → seed → single body update → report) and all the token-economy rules are project-agnostic.

---

### `babysit-prs` &nbsp;·&nbsp; *mostly reusable*

End-to-end PR finalization for one or more open PRs. Spawns a **single background orchestrator** that:

1. **Phase A** — handles Copilot review for every PR in **parallel** (one background subagent per PR). Each one polls until Copilot's review lands, decides validity per the repo's CLAUDE.md PR-Workflow conventions, implements valid fixes, pushes, replies to every thread, and resolves them.
2. **Phase B** — runs `verify-manual-tests` **sequentially** per PR (Playwright is single-instance).
3. Returns one compact final report when every PR is merge-ready.

The orchestrator pattern is the key win for **token economy**: only its single final return value lands in the calling session. Per-PR review chatter, tool calls, and intermediate summaries stay inside the subagents. The user can keep working in the parent session while it runs in the background.

Highlights:
- **One background dispatch from the main session, no per-PR direct dispatches** — keeps your conversation context tiny.
- **`ScheduleWakeup 270s`** for Copilot polling — stays inside the prompt-cache window, no idle token burn.
- **Per-PR push notifications** as each one completes (`READY ✅` or `BLOCKED ⚠`).
- **Resume support** via `/tmp/babysit-<pr>-{review-done,tested}` markers — kill mid-run, re-invoke later, only the unfinished work is repeated.
- **Stop conditions** include a 5-hour-rate-limit guard that catches 429s, best-effort `claude /usage` probe, and a "Phase A took >2.5h → don't start Phase B" heuristic so a long review run won't blow your token budget mid-test.
- **Strict failure handling** — if a Copilot comment requires a product decision the orchestrator can't make alone, it surfaces as a blocker rather than guessing.

**Invocation:** `/babysit-prs <repo>:<pr> [<repo>:<pr> ...]` — e.g. `/babysit-prs be:188 fe:256 client:166`

**Trigger phrases:** "babysit", "finalize PRs", "ready for merge", "handle reviews and tests", "auto-handle PRs"

**Requirements:**
- `gh` CLI authenticated against the target GitHub repos
- Working trees for each repo present at predictable paths (see "to adapt" below)
- Dev servers running (Phase B delegates to `verify-manual-tests` which depends on this) — install that skill too
- A `## Manual Testing` section in each PR body
- Each repo's CLAUDE.md describes its PR Workflow (replies, resolves, quality gates) — the orchestrator reads from there

**To adapt to your project:**
- Replace the **Repo map** at the top of the skill (3 hardcoded entries: `be`, `fe`, `client` → ridebly paths + `Knorcedger/ridebly-*` GitHub repos).
- Update the **quality-gate commands** in the orchestrator's Phase-A child task — currently `lint+typecheck+jest` for `be`, `lint+build` for `fe`/`client`.
- Everything else (orchestrator architecture, marker scheme, stop conditions, token-budget rules, report format) is project-agnostic.

If you have N projects with a similar layout, you can either swap the map or extend it (it's a small markdown table).

---

## Both skills together

Install `babysit-prs` and it'll automatically delegate Phase B to `verify-manual-tests` if you have it installed. They're designed to compose — `verify-manual-tests` runs standalone for one-off PR testing, and `babysit-prs` orchestrates it for multi-PR runs.

```bash
curl -fsSL https://raw.githubusercontent.com/dimokol/usefull-agent-skills/main/install.sh | bash
# installs both skills
```

---

## How skills work in Claude Code

Skills are markdown files that Claude Code loads (lazily) on demand. When the user asks Claude to do something matching a skill's `description`, or invokes it by name via the `Skill` tool, Claude reads the file and follows its instructions exactly.

Skills live in `~/.claude/skills/<skill-name>/SKILL.md`. Adding a new file there and restarting the session is all that's needed — no plugin registration, no settings editing.

**Skill metadata** (the YAML `name` + `description`) is loaded into every session's context (cheap — one line per skill). Skill **bodies** are only loaded when invoked, so you can have many skills installed without bloating context.

---

## License

MIT
