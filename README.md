# useful-agent-skills

A small collection of agent skills for AI-assisted development workflows. Authored in Claude/Codex-style `SKILL.md` format.

> ⚠️ **These skills were written for the [Ridebly](https://github.com/Knorcedger) monorepo's workflow.** They reference Ridebly-specific paths, port numbers (host `3100`/`4100` for the e2e stack), branch names (`dev`), and tooling assumptions. To reuse them elsewhere you **must** adjust those bits manually — every skill's body calls out exactly where. They are published here as a reference architecture, not a turnkey solution.

Each skill is a single self-contained markdown file. Install into the skill directory your agent uses:

- Claude Code: `~/.claude/skills/`
- Codex: `~/.codex/skills/`

> **Companion extension if you run multiple Claude Code agents at once:** [**Claude Notifications**](https://marketplace.visualstudio.com/items?itemName=dimokol.claude-notifications) — sound + OS banner when any agent finishes, with one-click *focus the exact VS Code terminal that fired the notification*. Pairs natively with `babysit-prs` for per-PR completion alerts.

---

## Install

### Claude Code one-liner

Install all skills (default — current set is just `babysit-prs`):

```bash
curl -fsSL https://raw.githubusercontent.com/dimokol/usefull-agent-skills/main/install.sh | bash
```

Install a specific skill by name:

```bash
curl -fsSL https://raw.githubusercontent.com/dimokol/usefull-agent-skills/main/install.sh | bash -s babysit-prs
```

Then **restart Claude Code** (or open a new session) — skills are picked up on session start.

### Codex install

```bash
SKILLS_DIR="$HOME/.codex/skills" \
  bash <(curl -fsSL https://raw.githubusercontent.com/dimokol/usefull-agent-skills/main/install.sh)
```

### Manual install

```bash
AGENT_SKILLS_DIR="$HOME/.claude/skills" # or "$HOME/.codex/skills"
mkdir -p "$AGENT_SKILLS_DIR/<skill-name>"
curl -fsSL https://raw.githubusercontent.com/dimokol/usefull-agent-skills/main/skills/<skill-name>/SKILL.md \
  -o "$AGENT_SKILLS_DIR/<skill-name>/SKILL.md"
```

---

## Skills

### `babysit-prs` &nbsp;·&nbsp; *mostly reusable*

End-to-end PR finalization for one or more open PRs. The calling session dispatches **one background subagent per PR** (parallel) and returns control immediately. Each subagent independently:

1. Waits for Copilot's review (cap 30 min).
2. For every Copilot comment: reads the referenced code, judges validity per the repo's `CLAUDE.md` PR-Workflow conventions, fixes valid items (commit + push, no `--amend`), replies to every thread, resolves them.
3. Runs the repo's quality gate (`lint && build` or `lint && typecheck && test`) inside an isolated git worktree.
4. For FE PRs: runs the local Playwright e2e suite (`npm run test:e2e:full`). The harness boots its own ephemeral docker stack on host ports `3100`/`4100`, so a filesystem lock (`/tmp/babysit-e2e-stack.lock`) serializes the e2e step across concurrent PRs.
5. Returns ONE JSON line: `{"pr": N, "status": "READY|BLOCKED", "applied": [...], "declined": N, "e2e": "X/Y", "blockers": [...]}`.

Highlights:

- **Isolated worktrees per PR** — no main-checkout collisions. `node_modules` and `.env` are symlinked from the main checkout (never `npm install` inside a worktree).
- **Resume support** via `/tmp/babysit-<pr>-{review-done,tested,done}` markers. Per-PR status JSON at `/tmp/babysit-<pr>-status.json`.
- **Stop conditions** — 5-hour rate-limit guard, 4-hour wall-clock no-progress timeout, 3-strikes-on-the-same-op rule.
- **Failure classification table** — auto-fix vs. report-blocker is explicit and bounded.
- **Per-PR completion notification** via `PushNotification` — one banner per PR completion, pairs natively with the Claude Notifications extension below.

**Invocation:** `/babysit-prs <repo>:<pr> [<repo>:<pr> ...]` — e.g. `/babysit-prs be:188 fe:256 client:166`

**Trigger phrases:** "babysit", "finalize PRs", "ready for merge", "handle reviews and tests", "auto-handle PRs"

**Requirements:**
- `gh` CLI authenticated against the target GitHub repos.
- Git worktrees enabled (default).
- For e2e: Docker daemon running; host ports `3100`/`4100` free.
- Each repo's `CLAUDE.md` describes its PR Workflow — the orchestrator reads from there.

**To adapt to your project:**
- Replace the **Repo map** at the top of the skill (entries `be`/`fe`/`client` with Ridebly paths and `Knorcedger/ridebly-*` GitHub repos).
- Update the **quality-gate commands** — currently `lint && typecheck && PORT=4001 npm test` for `be`, `lint && build` for `fe`/`client`.
- Update the **e2e command + lock name** if your harness uses different ports or a different invocation than `npm run test:e2e:full` on ports `3100`/`4100`.
- Update the **base-branch reference** (`dev`) and any other naming conventions your repo uses.

Everything else (subagent architecture, marker scheme, stop conditions, JSON return format) is project-agnostic.

### 🔔 Recommended pairing: Claude Notifications

If you run multiple Claude Code sessions, install **[Claude Notifications](https://marketplace.visualstudio.com/items?itemName=dimokol.claude-notifications)** (`dimokol.claude-notifications`):

- Per-PR sound + OS banner the moment each `babysit-prs` subagent completes.
- One-click terminal focus — jumps you straight to the exact VS Code window/tab where the agent fired.
- Per-session stage-dedup — exactly one notification per stage, never zero, never two.
- Works on macOS, Windows, and Linux.

Zero-config: `babysit-prs` already calls `PushNotification` at every per-PR completion.

---

### `verify-manual-tests` &nbsp;·&nbsp; ❌ *deprecated*

Was: an LLM-in-loop runner that drove Playwright MCP through prose `## Manual Testing` checklists in a PR body.

**Superseded by deterministic Playwright e2e specs.** When you can write `playwright/e2e/*.spec.ts` and run them with `npm run test:e2e:full`, there is no reason for an LLM to drive the browser — the spec *is* the test. The earlier `babysit-prs` invoked this skill in its Phase B; the current `babysit-prs` calls the e2e suite directly instead.

The file is retained as a tombstone (`skills/verify-manual-tests/SKILL.md`) explaining the deprecation. Don't install it.

---

## How skills work

Skills are markdown files that compatible agents load on demand. When the user asks for something matching a skill's `description`, or invokes it by name, the agent reads the file and follows its instructions.

Skills live at `<agent-skills-dir>/<skill-name>/SKILL.md`. Adding a new file there and restarting the session is all that's needed — no plugin registration or settings editing.

**Skill metadata** (the YAML `name` + `description`) is loaded into every session's context (cheap — one line per skill). Skill **bodies** are only loaded when invoked, so you can have many skills installed without bloating context.

---

## License

MIT
