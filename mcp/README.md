# MCP servers

Local [MCP](https://modelcontextprotocol.io) servers you wire into a project.
Unlike the `skills/` (which drop a `SKILL.md` into your agent's skills dir), these
are small programs you point your agent's MCP config at, per project.

| Server | What it does |
|---|---|
| [agent-chat](agent-chat/) 🟢 | A shared, titled, cross-agent chat so multiple CLI agents (Claude Code + Codex, in separate terminals) can deliberate and review each other's work without a human relaying messages. Blocking `wait` means idle agents burn no tokens. Zero dependencies. |

Each server has its own README with an installer and copy-paste config examples.
After installing one, **restart / reconnect the MCP server in each terminal** so
the tools load.
