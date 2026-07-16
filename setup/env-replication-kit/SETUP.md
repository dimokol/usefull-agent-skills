# Env replication kit

Replicates an existing Claude Code environment onto another machine or OS,
including Windows: shared skills, conversation history, your working
agreement, and a tuned `settings.json`, without carrying secrets in the
repo.

## Philosophy

- **Backup first.** Before touching anything on the target machine, copy
  what's already there. If a step below would overwrite a file, stop and
  back it up (or refuse) instead of clobbering silently.
- **Never clobber, always merge.** Every step that touches an existing
  file merges into it; nothing wholesale-replaces a file that already has
  content you didn't put there.
- **No secrets in the repo, ever.** This kit ships structure and
  placeholders only. A real OAuth token, API key, or connection string
  must never be committed, not even on a "just for this machine" branch.

## The key correction: `settings.json` is per-account

It's tempting to symlink or hardlink one `settings.json` across every
account on a machine, the same way you'd share skills or history. Don't.
`settings.json` carries `env.CLAUDE_CODE_OAUTH_TOKEN`, and that token IS
the account. Share the file and you've merged two accounts' auth into
one: both now authenticate as whichever token was written last.

What actually is portable across accounts, and across machines, is the
union-merge of two fields:

- `permissions.allow`, so you don't re-approve the same tool patterns
  account by account.
- `enabledPlugins`, so every account gets the same skill set.

Everything else in `settings.json` (the token, and anything genuinely
per-account like an effort-level preference) stays local to that one
file, on that one account.

`settings.reference.json` in this folder is that portable slice: a full
example `settings.json` with the token replaced by a placeholder, ready
to merge into any account's real file.

## Mental model

- `CLAUDE_CONFIG_DIR` points Claude Code at a config directory. Each
  account is its own directory.
- `CLAUDE_CODE_OAUTH_TOKEN` overrides any stored credential; it takes
  precedence over `/login` and any OS credential store.
- A small state file records a persistent default account, read on shell
  startup so plain `claude` opens the right one without setting an env
  var every time.
- Two things are worth sharing across accounts on the same machine:
  `projects/` (conversation transcripts, so `/resume` shows the same
  list under any account) and `history.jsonl` (prompt up-arrow recall).
  Share them via NTFS junctions/hardlinks on Windows, or plain symlinks
  on macOS/Linux. `skills/` and `plugins/` are usually worth sharing too,
  for the same reason `enabledPlugins` gets merged: one skill set, every
  account.

## Setup, Windows (PowerShell)

Run as a single block in a regular PowerShell window. No admin rights
needed: this uses NTFS junctions (`mklink /J`) for shared directories,
which work for any user without elevation. It's idempotent for a fresh
machine; if either account directory already exists, it stops and asks
you to resolve manually first.

```powershell
# --- 0. Sanity ---
Set-Location $HOME
if (Test-Path .\.claude-acct-a) { Write-Error ".claude-acct-a already exists, abort"; return }
if (Test-Path .\.claude-acct-b) { Write-Error ".claude-acct-b already exists, abort"; return }

# --- 1. Create the account directories and a shared directory ---
New-Item -ItemType Directory -Path .\.claude-acct-a, .\.claude-acct-b | Out-Null
New-Item -ItemType Directory -Path .\.claude-shared, .\.claude-shared\projects, .\.claude-shared\skills | Out-Null
New-Item -ItemType File -Path .\.claude-shared\history.jsonl -Force | Out-Null

# --- 2. Wire shared dirs/files into both accounts ---
# (cmd /c is used because mklink is a cmd builtin, not a PowerShell cmdlet)

# Conversations: shared, so /resume shows the same list under either account
cmd /c mklink /J "$HOME\.claude-acct-a\projects" "$HOME\.claude-shared\projects" | Out-Null
cmd /c mklink /J "$HOME\.claude-acct-b\projects" "$HOME\.claude-shared\projects" | Out-Null

# Prompt history: hardlink, because mklink /J only works on directories
cmd /c mklink /H "$HOME\.claude-acct-a\history.jsonl" "$HOME\.claude-shared\history.jsonl" | Out-Null
cmd /c mklink /H "$HOME\.claude-acct-b\history.jsonl" "$HOME\.claude-shared\history.jsonl" | Out-Null

# Skills: same skill set in every account
cmd /c mklink /J "$HOME\.claude-acct-a\skills" "$HOME\.claude-shared\skills" | Out-Null
cmd /c mklink /J "$HOME\.claude-acct-b\skills" "$HOME\.claude-shared\skills" | Out-Null

# Settings: PER-ACCOUNT (each holds its own OAuth token). Do NOT link this one.
Set-Content "$HOME\.claude-acct-a\settings.json" '{ "env": { "CLAUDE_CODE_OAUTH_TOKEN": "<ACCT_A_TOKEN>" } }'
Set-Content "$HOME\.claude-acct-b\settings.json" '{ "env": { "CLAUDE_CODE_OAUTH_TOKEN": "<ACCT_B_TOKEN>" } }'
# Then merge settings.reference.json into each, per "Applying settings.reference.json" below.

# Plugins: same installed plugins in every account
New-Item -ItemType Directory -Path "$HOME\.claude-shared\plugins" | Out-Null
cmd /c mklink /J "$HOME\.claude-acct-a\plugins" "$HOME\.claude-shared\plugins" | Out-Null
cmd /c mklink /J "$HOME\.claude-acct-b\plugins" "$HOME\.claude-shared\plugins" | Out-Null

# --- 3. Append the multi-account block to the PowerShell profile ---
if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }

$block = @'

# ===== Claude Code multi-account =====
# Paste real tokens (from `claude setup-token`) here, on the target machine only.
# Never commit or sync these values anywhere.
$env:CLAUDE_TOKEN_ACCT_A = '<ACCT_A_TOKEN>'
$env:CLAUDE_TOKEN_ACCT_B = '<ACCT_B_TOKEN>'

function claude-acct-a {
    $env:CLAUDE_CONFIG_DIR = "$HOME\.claude-acct-a"
    $env:CLAUDE_CODE_OAUTH_TOKEN = $env:CLAUDE_TOKEN_ACCT_A
    & claude @args
}
function claude-acct-b {
    $env:CLAUDE_CONFIG_DIR = "$HOME\.claude-acct-b"
    $env:CLAUDE_CODE_OAUTH_TOKEN = $env:CLAUDE_TOKEN_ACCT_B
    & claude @args
}

# This-shell-only switchers (do not persist across new terminals)
function claude-use-acct-a { $env:CLAUDE_CONFIG_DIR = "$HOME\.claude-acct-a"; $env:CLAUDE_CODE_OAUTH_TOKEN = $env:CLAUDE_TOKEN_ACCT_A; Write-Host "Claude account: acct-a (this shell)" }
function claude-use-acct-b { $env:CLAUDE_CONFIG_DIR = "$HOME\.claude-acct-b"; $env:CLAUDE_CODE_OAUTH_TOKEN = $env:CLAUDE_TOKEN_ACCT_B; Write-Host "Claude account: acct-b (this shell)" }
function claude-use-default { Remove-Item Env:CLAUDE_CONFIG_DIR, Env:CLAUDE_CODE_OAUTH_TOKEN -ErrorAction SilentlyContinue; Write-Host "Claude account: default (this shell)" }

# Persistent default, written to a state file every new shell reads on startup
function claude-use-acct-a-gl { Set-Content "$HOME\.claude-active-profile" "acct-a"; claude-use-acct-a; Write-Host "  -> persisted as global default" }
function claude-use-acct-b-gl { Set-Content "$HOME\.claude-active-profile" "acct-b"; claude-use-acct-b; Write-Host "  -> persisted as global default" }
function claude-use-default-gl { Remove-Item "$HOME\.claude-active-profile" -ErrorAction SilentlyContinue; claude-use-default; Write-Host "  -> persisted as global default" }

function claude-which {
    $persisted = if (Test-Path "$HOME\.claude-active-profile") { Get-Content "$HOME\.claude-active-profile" } else { "(none)" }
    $active = "default"
    if ($env:CLAUDE_CONFIG_DIR -eq "$HOME\.claude-acct-a") { $active = "acct-a" }
    if ($env:CLAUDE_CONFIG_DIR -eq "$HOME\.claude-acct-b") { $active = "acct-b" }
    Write-Host "Active in this shell: $active"
    Write-Host "Persistent default:   $persisted"
}

# Apply the persistent default at shell startup
if (Test-Path "$HOME\.claude-active-profile") {
    switch ((Get-Content "$HOME\.claude-active-profile").Trim()) {
        'acct-a' { $env:CLAUDE_CONFIG_DIR = "$HOME\.claude-acct-a"; $env:CLAUDE_CODE_OAUTH_TOKEN = $env:CLAUDE_TOKEN_ACCT_A }
        'acct-b' { $env:CLAUDE_CONFIG_DIR = "$HOME\.claude-acct-b"; $env:CLAUDE_CODE_OAUTH_TOKEN = $env:CLAUDE_TOKEN_ACCT_B }
    }
}
# ===== end Claude Code multi-account =====
'@

Add-Content -Path $PROFILE -Value $block

# --- 4. Tighten profile permissions (it now contains tokens) ---
icacls $PROFILE /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null
```

Open a new PowerShell window afterward. `claude-acct-a` / `claude-acct-b`
open each account directly; `claude-use-acct-a-gl` sets a persistent
default for plain `claude`; `claude-which` shows what's active.

## Setup, macOS/Linux (symlinks)

Same layout, real symlinks instead of junctions/hardlinks:

```
~/.claude                 symlink -> ~/.claude-acct-a   (or whichever is your default)
~/.claude-acct-a/         per-account state
  projects/              -> symlink to ~/.claude-shared/projects
  history.jsonl          -> symlink to ~/.claude-shared/history.jsonl
  settings.json            REAL per-account file, holds this account's token, never shared
  skills/                -> symlink to ~/.claude-shared/skills
  plugins/               -> symlink to ~/.claude-shared/plugins
~/.claude-acct-b/         same structure, same shared targets
~/.claude-shared/         single source of truth for everything that's actually shared
```

Wire it with `ln -s`, and add the equivalent function block to
`~/.zshrc` (same functions, same names, zsh syntax instead of
PowerShell). Back up any existing `~/.claude` before you touch it, since
it's the one thing this whole kit could clobber by accident.

## Applying `settings.reference.json`

For each account:

1. Read that account's current `settings.json` and note its
   `env.CLAUDE_CODE_OAUTH_TOKEN` (generate one with `claude setup-token`,
   run as that account, if it doesn't have one yet).
2. Take `settings.reference.json`, replace `<paste-your-token>` with that
   account's real token, and merge it into the account's existing file:
   reference values win for keys it defines, but keep any keys the
   existing file already has that the reference doesn't mention. If the
   existing file is effectively empty, the filled-in reference can
   replace it wholesale.
3. Validate: the file must parse as JSON, and launching that account must
   not demand `/login`.

Trim or extend `permissions.allow` and `enabledPlugins` in the reference
file to match your own toolchain; they're illustrative, not exhaustive.

## Sharing project memory without clobbering it

Skills, history, and plugins are safe to link wholesale because they're
append-only or identical-by-design across accounts. Project memory (the
per-project notes an agent accumulates under a config dir's
`projects/<slug>/memory/` path) is different: two accounts working the
same project can genuinely diverge, so a blind link or overwrite loses
one side's notes.

Use copy-if-absent instead of link-or-overwrite: for each project the
source machine knows about, copy its `memory/` directory into the target
only if the target doesn't already have one for that project. Never
overwrite an existing target memory file.

```bash
# macOS/Linux; adapt paths for Windows (Copy-Item -Recurse with the same guard)
SRC="$HOME/.claude-shared-backup/projects"
DST="$HOME/.claude-acct-a/projects"

for proj in "$SRC"/*/; do
  slug="$(basename "$proj")"
  if [ -d "$proj/memory" ] && [ ! -d "$DST/$slug/memory" ]; then
    mkdir -p "$DST/$slug"
    cp -R "$proj/memory" "$DST/$slug/memory"
    echo "seeded memory for $slug"
  fi
done
```

Run this once per new account or machine, from a backup of the source
you're replicating, never from a live shared directory (that would
defeat the point: memory needs to stay per-account once it's seeded).

## What was deliberately stripped, and why

- **Hooks.** Hooks in a working `settings.json` are usually path- or
  project-specific (guard scripts, resource gates tied to particular
  repos on a particular machine). Copying them blind just makes them
  error on a machine that doesn't have those paths. Review each hook and
  either adapt it or drop it; don't copy-paste.
- **A notification/companion extension's own hooks.** If you use an
  editor extension that adds Claude Code hooks for cross-session
  notifications, let its installer write those hooks itself. Don't
  hand-author them into `settings.reference.json`; they change with the
  extension's own versioning.
- **Experimental env vars and feature flags.** Anything turned on for
  personal experimentation (a custom model alias, an opt-in fast-mode
  flag) isn't part of a base setup. Add it back per account, deliberately,
  if you still want it.
- **Tokens.** Never in this kit. Generated per account, per machine,
  applied by hand at setup time.
- **Transcripts, history, and memory.** These stay machine-local by
  design; sharing them is between accounts on one machine, not between
  machines. Each account's server-side history (web, mobile, other
  devices) stays independent regardless of what you link locally.

## Verify checklist

1. Both accounts launch without `/login`: `claude-acct-a` (or the
   macOS/zsh equivalent) and `claude-acct-b` each open straight into a
   session.
2. `/resume` shows the same conversation list under either account
   (confirms `projects/` is actually shared).
3. Up-arrow recall shows the same recent prompts under either account
   (confirms `history.jsonl` is shared).
4. `/plugins` lists the same plugin set under both accounts.
5. `claude-which` reports the expected active and persistent account.
6. `claude-use-acct-a-gl`, then a brand-new terminal, then plain
   `claude`: opens as acct-a.
7. `settings.json` in each account parses as valid JSON and contains
   that account's own token, not the other account's and not the
   placeholder.
