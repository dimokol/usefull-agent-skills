# Dev-environment doctor

Paste this whole prompt into a fresh Claude Code session on a new machine.
It gets that machine's tooling into a correct, consistent agent-dev state,
and verifies it. Assume Claude Code is already installed (that's how you're
reading this). Work autonomously; only stop for the interactive logins
listed below.

Edit only the CONFIG block before you paste. Everything else is portable
as-is.

---

You are this machine's dev-environment doctor. Get THIS machine into a
correct, consistent agent-dev state, and verify it.

## CONFIG (the only thing you edit)

- Node: install fnm (via brew) plus the latest Node LTS as the global
  baseline. Per-project versions are NOT pinned here: fnm switches
  automatically from each repo's `.node-version` / `.nvmrc`, and MUST
  auto-install a missing version on `cd` (configure fnm's shell hook with
  install-on-cd).
- Homebrew tools: `{your CLI tools, e.g. gh, vercel, your hosting
  platform's CLI, your DB shell}`
- Interactive logins (cannot be automated): `{your login CLIs}`
  - gh → `gh auth login`, verify with `gh auth status`
  - vercel → `vercel login`, verify with `vercel whoami`
  - `<your-host-cli>` → `<your-host-cli> login`, verify with
    `<your-host-cli> whoami`
      If a backend's credentials live as config vars on a hosting
      platform's CLI, see the REFERENCE section below for how to read one
      out safely.
- MCP servers (Claude Code, HTTP transport, add with `claude mcp add`):
  `{your MCP servers: name + url}`
  - `<your-internal-tool>` → `https://<your-mcp-host>/api/mcp`
      Per-user token. The human gets it from their own account/profile
      page and pastes it at the moment of use. Never write a real token
      into this CONFIG block; it should only ever hold names and URLs.
  - `<your-hosted-oauth-service>` → `https://<hosted-mcp-url>`
      Hosted, OAuth. Claude Code opens a browser on first use; there's no
      token to manage or lose.
- Claude Code plugins (agent skills, driven by the `claude` CLI so this
  prompt can install them non-interactively): `{your plugins}`
  - `<plugin-name>` (`<marketplace-org>`), e.g. `modern-web-guidance`
    (`GoogleChrome`) for on-demand web-platform guidance. Install via:
      `claude plugin marketplace add <org>/<repo>`
      `claude plugin install <plugin-name>@<marketplace>`
    Verify with `claude plugin list` (the plugin name appears). Newly
    installed plugins apply to the next Claude Code session; the current
    session won't see them until restart. Note this in the status table,
    but don't restart yourself.
- Optional, only if run inside a project dir (has package.json + .vercel):
  - `vercel env pull .env.local`

## OPERATING RULES

1. Idempotent: every step must no-op cleanly if already healthy. Re-running
   this prompt on a healthy machine must change nothing and end all-green.
2. Detect, fix, VERIFY. "Installed" is not "works." Always run the verify
   command, never just `which`.
3. Auto-install silently. Pause ONLY for the interactive logins. For each:
   print the exact command, ask "Run now? [Y/n]", run it in the foreground
   so the browser/2FA flow works, then re-run its verify command.
4. Secrets: never echo, log, or write a token. Logins run interactively in
   the foreground; the CLIs store their own credentials. MCP bearer tokens
   are pasted by the human at the moment of use and passed only to
   `claude mcp add`, never hardcoded here or persisted anywhere else.
5. macOS reality: detect the Homebrew prefix (`/opt/homebrew` on Apple
   Silicon, `/usr/local` on Intel) and ensure it's on PATH via
   `~/.zprofile` (zsh is the default shell). Don't assume bash 4+ features
   in any shell you run.
6. Don't touch private project repos or pull env vars unless you were
   started inside such a repo and the user confirms.

## SEQUENCE

1. Report the machine: chip (arm64/x86_64), macOS version, Homebrew
   prefix.
2. Xcode Command Line Tools: if `xcode-select -p` fails, trigger
   `xcode-select --install`, then wait/poll until it resolves.
3. Homebrew: install if missing; ensure the prefix is on PATH in
   `~/.zprofile`.
4. Node: install fnm via brew if missing; wire its zsh hook into
   `~/.zprofile`/`.zshrc` WITH auto-install-on-cd so an uninstalled
   per-project version fetches itself. Install the latest Node LTS as the
   global default (`fnm install --lts` + `fnm default`). Verify `node -v`
   works outside any project. Do NOT pin a project version here; each
   repo's `.node-version` is fnm's job at `cd` time.
5. Homebrew tools: install any missing CONFIG tool, then verify each one
   runs. Then check for stale versions: run `brew outdated` against the
   brew-managed tools listed in CONFIG, `brew upgrade` each that's behind,
   then re-verify. These tools drift fast; a stale CLI causes silent
   compat issues with whatever platform it talks to, and is the most
   common "worked last week, broken today" cause on a re-pasted doctor
   run.
6. Logins: for each CONFIG login, run its verify command; if not
   authenticated, do the Rule-3 prompt-and-run flow.
7. MCP servers: run `claude mcp list`. For each CONFIG server not already
   connected, add it: `claude mcp add --transport http <name> <url>`
   (servers that need a per-user bearer token also pass
   `--header "Authorization: Bearer <token>"`, pasted by the human at that
   moment per CONFIG, Rules 3/4; OAuth-based servers need no token, Claude
   Code opens a browser on first use). Then re-run `claude mcp list` and
   confirm each shows connected, not merely configured. Skip any already
   connected. If an OAuth handshake fails because the engineer doesn't
   have access to that service yet, stop and tell them who to ask for
   provisioning; re-run the doctor afterwards.
8. Claude Code plugins: run `claude plugin list` to see installed
   plugins. For each CONFIG plugin not already present, run its bash
   install commands from the CONFIG block (`claude plugin marketplace
   add …` then `claude plugin install …`). Re-run `claude plugin list`
   and confirm the plugin is present. Skip any already installed.
9. Optional env pull: only if started in a project dir and the user
   confirms.

## OUTPUT

End with a single aligned status table, one row per check, using
✅ / ⚠️ / ❌, then a one-line verdict. If anything is ❌, list the exact
remaining manual step(s). Be terse; no narration during the run beyond the
table and the login prompts.

## REFERENCE: reading a secret from your host's config vars, safely

Not part of the doctor run itself; a discipline for the human (and future
agents) working on this machine whenever a backend's credentials live as
config vars on a hosting platform's CLI.

1. List config-var KEYS ONLY, never values, on the first pass:

       `<host-cli> config -s -a <app> | cut -d= -f1 | sort`

   Never run the plain "dump everything" form of your host's config
   command. It prints every value (API keys, OAuth secrets, webhook
   signing keys, database URLs, and so on) straight into your terminal,
   and into an agent's transcript if an agent runs it.
2. Fetch exactly one value once you know which key you need:

       `<host-cli> config:get <KEY> -a <app>`

   The value appears on stdout. From this point, treat that line as a
   secret.
3. Feed it through process substitution so it never lands as a literal
   string in your shell history:

       ` some-tool "$(<host-cli> config:get <KEY> -a <app>)"`

   A leading space keeps the command itself out of zsh history (requires
   `setopt HIST_IGNORE_SPACE`). The value is briefly visible to `ps` while
   the tool runs, which is usually acceptable on a single-user dev
   machine; for frequent use, prefer a GUI client with its own encrypted
   credential store so the secret stops touching the shell at all.
4. Treat any connection string or token like a password: don't paste it
   into chat, write it to disk, echo it into an agent's transcript, or
   commit it. If it does leak, rotate it at the source (the database or
   service that issued it). Rotating the host's config var alone does not
   invalidate a connection string that's already been exposed.
5. An agent should ask the human to run the lookup and paste back only
   the specific result needed, rather than running the fetch itself. An
   agent running step 2 directly lands the secret in its own tool-result
   transcript, which is itself a leak surface.
