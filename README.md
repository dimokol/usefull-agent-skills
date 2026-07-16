# useful-agent-skills

A hub of agent skills, guardrail hooks, and workflow patterns for AI-assisted development brought to life from everyday needs working on multiple large scale projects simoultaniously. To deem reuseable, some content in this repo is generalized, stripped of project specific paths and internal setup, explaining how it could apply to any project/workflow instead.

**Portability legend:** 🟢 generic (works as-is) · 🟡 adapt-via-config (fill placeholders in your CLAUDE.md).

## Areas

| Area | What's in it |
|---|---|
| [🛠 Skills](skills/) | Reusable `SKILL.md` workflows: PR finalize, branch safety, task sync, worktree QA. |
| [🪝 Hooks](hooks/) | Guardrail hooks that block risky agent actions (no-auto-merge, PR↔task link). |
| [📊 Statusline monitor](statusline/) | Live machine-pressure badge + a heavy-op gate for multi-agent workflows to prevent exploding laptops. |
| [📋 CLAUDE.md blocks](claude-md/) | Copy-paste instruction blocks: a global working agreement + project standards. |
| [✍️ AI writing tone](tone/) | Make agent-written text read human, plus a product-copy voice guide. |
| [📚 Doc organization](docs-organization/) | How to structure `docs/`, write handoffs, and index "change X → edit here". |
| [⚙️ Getting set up](setup/) | A dev-environment bootstrap prompt, a cross-machine replication kit, ecosystem picks. |

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

Then **restart Claude Code** (or open a new session). Skills are picked up on session start.

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

> **Companion extension if you run multiple Claude Code agents at once:** [**Claude Notifications**](https://marketplace.visualstudio.com/items?itemName=dimokol.claude-notifications) (sound + OS banner when any agent finishes, with one-click *focus the exact VS Code terminal that fired the notification*). Pairs natively with `babysit-prs` for per-PR completion alerts.
