# useful-agent-skills

A small collection of agent skills for AI-assisted development workflows. Authored in Claude/Codex-style `SKILL.md` format.

> **Portable with config in your project's `CLAUDE.md`.** Earlier versions of this repo hard-coded one project's paths, branch names, and ports. The current `babysit-prs` and `e2e-harness-patterns` skills are **project-agnostic**: drop a `babysit-prs Configuration` section into your CLAUDE.md (see [`templates/CLAUDE.md-additions.md`](templates/CLAUDE.md-additions.md)) and the skill reads from there. See [`skills/babysit-prs/PRECONDITIONS.md`](skills/babysit-prs/PRECONDITIONS.md) for what your project needs.

Each skill is a self-contained markdown file. Install into the skill directory your agent uses:

- Claude Code: `~/.claude/skills/`
- Codex: `~/.codex/skills/`

> **Companion extension if you run multiple Claude Code agents at once:** [**Claude Notifications**](https://marketplace.visualstudio.com/items?itemName=dimokol.claude-notifications) — sound + OS banner when any agent finishes, with one-click *focus the exact VS Code terminal that fired the notification*. Pairs natively with `babysit-prs` for per-PR completion alerts.

---

## Install

### Claude Code one-liner

Install all skills:

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

| Skill | Status | What it does |
|---|---|---|
| [`babysit-prs`](skills/babysit-prs/SKILL.md) | **active, portable** | End-to-end PR finalization. One subagent per PR, parallel. Copilot review + self-review fallback + CI gate + local e2e (where applicable). |
| [`e2e-harness-patterns`](skills/e2e-harness-patterns/SKILL.md) | **active, reference** | Catalog of patterns for designing a local e2e harness — ephemeral stacks, dynamic ports, scope-based selection, session-bypass auth, lock-serialization, dual-speed iteration. Pairs with `babysit-prs`. |
| [`verify-manual-tests`](skills/verify-manual-tests/SKILL.md) | ❌ **deprecated** | LLM-in-loop runner for prose checklists; superseded by deterministic e2e specs. |

### `babysit-prs` highlights

End-to-end PR finalization for one or more open PRs. The calling session dispatches **one background subagent per PR** (parallel) and returns control immediately. Each subagent independently:

1. Detects whether Copilot has reviewed (fast-fail if Copilot has clearly errored or never posted within ~5 min of PR open).
2. If Copilot reviewed: reads each comment, judges validity per the repo's `CLAUDE.md`, fixes valid items, replies, resolves threads.
3. If Copilot did not review: self-reviews the diff against the project's `CLAUDE.md`, posts findings as a top-level PR comment, implements `[CRITICAL]` + `[WARNING]` findings as new commits.
4. Waits for CI green (`gh pr checks <pr> --watch`).
5. For repos with local e2e: runs the suite inside an isolated git worktree (lock-serialized across PRs).
6. Returns ONE JSON line: `{"pr": N, "status": "READY|BLOCKED", "applied": [...], "declined": N, "e2e": "...", "blockers": [...]}`.

**Invocation:** `/babysit-prs <key>:<pr> [<key>:<pr> ...]` — e.g. `/babysit-prs api:412 admin:188 portal:99`. Keys come from your CLAUDE.md repo map.

**Trigger phrases:** "babysit", "finalize PRs", "ready for merge", "handle reviews and tests", "auto-handle PRs".

**Requirements:** see [`skills/babysit-prs/PRECONDITIONS.md`](skills/babysit-prs/PRECONDITIONS.md).

**Configuration:** copy [`templates/CLAUDE.md-additions.md`](templates/CLAUDE.md-additions.md) into your project's CLAUDE.md and fill in your repo map.

### 🔔 Recommended pairing: Claude Notifications

If you run multiple Claude Code sessions, install **[Claude Notifications](https://marketplace.visualstudio.com/items?itemName=dimokol.claude-notifications)** (`dimokol.claude-notifications`):

- Per-PR sound + OS banner the moment each `babysit-prs` subagent completes.
- One-click terminal focus — jumps you straight to the exact VS Code window/tab where the agent fired.
- Per-session stage-dedup — exactly one notification per stage, never zero, never two.
- Works on macOS, Windows, and Linux.

Zero-config: `babysit-prs` already calls `PushNotification` at every per-PR completion.

---

## How skills work

Skills are markdown files that compatible agents load on demand. When the user asks for something matching a skill's `description`, or invokes it by name, the agent reads the file and follows its instructions.

Skills live at `<agent-skills-dir>/<skill-name>/SKILL.md`. Adding a new file there and restarting the session is all that's needed — no plugin registration or settings editing.

**Skill metadata** (the YAML `name` + `description`) is loaded into every session's context (cheap — one line per skill). Skill **bodies** are only loaded when invoked, so you can have many skills installed without bloating context.

---

## Contributing

Skills here are opinionated — they encode workflow decisions that have been tested under real PR / e2e load. PRs and issues are welcome, especially:

- Patterns that complement what's already here (alternate test-runner integrations, non-Docker harnesses, GitLab/Bitbucket adapters).
- Reports of preconditions or edge cases the docs don't cover.
- Generalizations that improve portability without sacrificing the rigor that made each skill earn its place.

Please don't propose narrowly project-specific skills — keep this repo focused on patterns that travel.

---

## License

MIT
