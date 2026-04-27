# useful-agent-skills

A collection of Claude Code skills for AI-assisted development workflows.

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
# Example for verify-manual-tests
mkdir -p ~/.claude/skills/verify-manual-tests
curl -fsSL https://raw.githubusercontent.com/dimokol/usefull-agent-skills/main/skills/verify-manual-tests/SKILL.md \
  -o ~/.claude/skills/verify-manual-tests/SKILL.md
```

---

## Skills

### `verify-manual-tests`

Automates the `## Manual Testing` checkboxes in a GitHub PR by driving running dev servers via Playwright MCP (Claude Code's browser automation). Each checkbox is executed inline — no subagents. Boxes flip to `[x]` only when the behavior is confirmed. Failures are left unchecked with a clear explanation.

**Trigger phrases:** "verify manual tests", "run PR manual tests", "check off the boxes", "auto-test the PR #N"

**Requirements:**
- Claude Code with Playwright MCP enabled
- `gh` CLI authenticated
- Dev servers already running (the skill checks, doesn't start them)

---

## How skills work in Claude Code

Skills are markdown files that Claude Code loads at session start. When you invoke a skill — either by asking Claude to use it by name, or via the `Skill` tool — Claude reads the file and follows its instructions exactly.

Skills live in `~/.claude/skills/<skill-name>/SKILL.md`. Adding a new file there and restarting the session is all that's needed.

---

## License

MIT
