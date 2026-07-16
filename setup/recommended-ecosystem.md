# Recommended ecosystem

A short, sourced answer to "what's actually worth running": the plugin set from a real working `settings.json`, one editor extension, one statusline, and MCP-server discipline. One line each, keep/skip reasoning where it matters, not a wall of text.

## Plugins

The `enabledPlugins` from a working `settings.json` (full snippet at the bottom). All from the official `claude-plugins-official` marketplace unless noted.

| Plugin | What it is / why it's worth it |
|---|---|
| [superpowers](https://github.com/obra/superpowers) | Skills-as-methodology: TDD, systematic debugging, brainstorming, plan writing and execution, verification, worktrees. The most broadly adopted third-party plugin; in the official marketplace since early 2026. |
| `typescript-lsp` | Official Anthropic LSP plugin. Wires a real TypeScript language server into the agent (diagnostics, go-to-definition, rename) instead of grep-only navigation. |
| `playwright` | Real browser automation for the agent: the standard way to give it a UI to click through for e2e tests or live debugging. |
| `vercel` | Deploy status, environment variables, and domain facts read straight from the source, so the agent stops guessing at deployment state. |
| `feature-dev` | Structured explore, plan, implement subagents for a feature, so the agent commits to an approach before it starts editing. |
| `pr-review-toolkit` | Specialist review subagents (correctness, simplification, comment accuracy, test coverage, silent failures, type design) to run on a diff before or during a PR. |
| `claude-md-management` | Keeps CLAUDE.md itself pruned and well-formed. Official guidance says a bloated instruction file gets ignored; this is the maintenance tool for that rule. |
| `frontend-design` | Design-quality guidance for UI work. One of the most-installed plugins in the official marketplace. |
| `skill-creator` | Scaffolds a new SKILL.md in the correct format, so a one-off workflow becomes a reusable skill instead of a copy-pasted prompt. |
| `swift-lsp` | Same idea as `typescript-lsp`, for Swift. Only worth enabling if you actually touch Swift/iOS/macOS code. |
| `figma` | Figma's official MCP-backed plugin. Two-way bridge between a Figma file and code: read a design into a component, or push a component back into Figma. |
| `modern-web-guidance` (marketplace: [GoogleChrome/modern-web-guidance](https://github.com/GoogleChrome/modern-web-guidance)) | On-demand web-platform guidance from Chrome DevRel. An example of a plugin worth adding from outside the official marketplace, via `extraKnownMarketplaces`. |

## Editor extension

[**Claude Notifications**](https://marketplace.visualstudio.com/items?itemName=dimokol.claude-notifications) (VS Code): sound and OS banner when any agent session finishes, with one-click focus of the exact terminal that fired it. Worth installing the moment you run more than one agent session at a time. Its repo's `CLAUDE.md` also doubles as a solid reference for building robust lifecycle hooks (Stop, Notification) if you're writing your own.

## Statusline

[**ccstatusline**](https://github.com/sirmalloc/ccstatusline): the most popular dedicated statusline (11k+ stars, actively maintained). Model, cost, context, and time segments, configurable via `npx ccstatusline@latest`. The default choice unless you're building something custom on top of it.

## MCP servers: keep it to 3 to 6

Every MCP server loaded costs context (tool definitions alone can eat well into six figures of tokens across a handful of heavy servers), and a widely cited audit puts server abandonment at roughly half of everything published (median 6 lifetime commits; methodology unverified but directionally consistent with community sentiment). Treat "add an MCP for everything" as the anti-pattern it is. A durable core, per the same research: one code-hosting server, one docs server, one browser server, nothing else unless you have a specific, recurring reason.

Keepers worth the context budget:

| Server | Why it earns its slot |
|---|---|
| [Context7](https://github.com/upstash/context7) | Up-to-date library docs on demand, so the agent stops working from stale training data. The most-installed docs server. |
| [chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp) | Real Chrome via the DevTools protocol; the default for browser debugging beyond simple click-throughs. |
| [github-mcp-server](https://github.com/github/github-mcp-server) | Official GitHub server. Worth noting: plenty of Claude Code users prefer the plain `gh` CLI instead, for better token economy in a CLI-native harness. |
| [serena](https://github.com/oraios/serena) | Semantic code search and editing via LSP. The main survivor of the "code-intelligence MCP" wave, though it now competes with Anthropic's own LSP plugins for the same job. |

Skip: filesystem, memory, and sequential-thinking servers, mostly superseded by Claude Code's native equivalents. Skip anything you installed once and haven't checked `claude mcp list` for since.

## Settings snippet

The plugin manifest above as it actually appears in a working `settings.json` (token redacted):

```json
{
  "env": {
    "CLAUDE_CODE_OAUTH_TOKEN": "<YOUR_TOKEN_HERE>"
  },
  "statusLine": {
    "type": "command",
    "command": "npx -y ccstatusline@latest"
  },
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "typescript-lsp@claude-plugins-official": true,
    "playwright@claude-plugins-official": true,
    "vercel@claude-plugins-official": true,
    "feature-dev@claude-plugins-official": true,
    "pr-review-toolkit@claude-plugins-official": true,
    "claude-md-management@claude-plugins-official": true,
    "frontend-design@claude-plugins-official": true,
    "skill-creator@claude-plugins-official": true,
    "swift-lsp@claude-plugins-official": true,
    "figma@claude-plugins-official": true,
    "modern-web-guidance@googlechrome": true
  },
  "extraKnownMarketplaces": {
    "googlechrome": {
      "source": { "source": "github", "repo": "GoogleChrome/modern-web-guidance" }
    }
  }
}
```

## Sources

https://github.com/obra/superpowers · https://github.com/GoogleChrome/modern-web-guidance · https://github.com/sirmalloc/ccstatusline · https://github.com/upstash/context7 · https://github.com/ChromeDevTools/chrome-devtools-mcp · https://github.com/github/github-mcp-server · https://github.com/oraios/serena · https://scottspence.com/posts/optimising-mcp-server-context-usage-in-claude-code · https://rapidclaw.dev/blog/mcp-servers-dead-what-it-means-2026 (abandonment stat, methodology unverified)
