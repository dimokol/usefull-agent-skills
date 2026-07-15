#!/bin/sh
# pretooluse-pressure: gate heavy Bash ops on machine pressure + cross-session concurrency.
#
# A Claude Code PreToolUse hook (matcher "Bash"). Fires before every Bash tool
# call. Reads tool_input.command from stdin JSON.
#
# Behavior (only for HEAVY ops: installs/e2e/docker/build/jest; everything else passes):
#   - concurrency: e2e and docker are capped at 1 across ALL sessions (counted live via
#     `pgrep`, so a crashed op never leaves a stale lock). Over the cap -> DENY.
#   - pressure: RED -> DENY (the only enforcement that survives --dangerously-skip-permissions);
#               AMBER -> non-blocking warning injected for the model to relay/consider.
#
# Fail-open everywhere: any parse/probe error -> allow. A monitoring bug must never block work.
# Escape hatch: prefix a command with PRESSURE_OVERRIDE=1 to bypass the gate.
#
# CONFIG (env vars, all optional):
#   PRESSURE_PROBE   path to pressure.sh (default: ~/.claude/pressure-monitor/pressure.sh)
#
# Reference: this area's README.md (statusline/README.md)

set -u
PROBE="${PRESSURE_PROBE:-$HOME/.claude/pressure-monitor/pressure.sh}"

input=$(cat 2>/dev/null) || exit 0
command -v jq >/dev/null 2>&1 || exit 0   # no jq -> fail open

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# explicit human override
case "$cmd" in *PRESSURE_OVERRIDE=1*) exit 0 ;; esac

# classify: only these are "heavy"; anything else passes silently
class=""
case "$cmd" in
  *test:e2e*|*e2e.sh*|*"playwright test"*)                 class="e2e" ;;
  *"docker compose"*|*docker-compose*|*"buildx"*|*"docker build"*) class="docker" ;;
  *"npm install"*|*"npm ci"*|*"npm i "*|*"pnpm install"*|*"yarn install"*) class="install" ;;
  *"npm run build"*|*"next build"*|*"tsc --build"*)        class="build" ;;
  *jest*)                                                  class="jest" ;;
esac
[ -z "$class" ] && exit 0

# live count of running ops in this class (across all sessions). No lockfiles -> no stale state.
pat=""
case "$class" in
  e2e)     pat="test:e2e|e2e\.sh|playwright test" ;;
  docker)  pat="docker compose|docker-compose|buildx|docker build" ;;
  install) pat="npm install|npm ci|pnpm install|yarn install" ;;
  build)   pat="npm run build|next build|tsc --build" ;;
  jest)    pat="[j]est " ;;
esac
running=0
[ -n "$pat" ] && running=$(pgrep -f "$pat" 2>/dev/null | wc -l | tr -d ' ')

# pressure (cached, ~10ms)
pj=$("$PROBE" --json 2>/dev/null)
level=$(printf '%s' "$pj" | jq -r '.level // "OK"' 2>/dev/null); level=${level:-OK}
summary=$(printf '%s' "$pj" | jq -r '"RAM \(.ram_pct)% · swap \(.swap_pct)% · load \(.load1) · disk \(.disk_free_gb)G"' 2>/dev/null)
[ -z "$summary" ] && summary="(pressure unavailable)"

emit() { # decision  reason
  printf '%s' "$2" | jq -Rs --arg d "$1" \
    '{hookSpecificOutput: ({hookEventName:"PreToolUse"} + (if $d=="deny" then {permissionDecision:"deny", permissionDecisionReason:.} else {additionalContext:.} end))}'
  exit 0
}

# 1) cross-session concurrency cap (e2e & docker only: safe + high value; e2e port-collides anyway)
if [ "$class" = "e2e" ] && [ "$running" -ge 1 ]; then
  emit deny "⛔ Coordination: an e2e run is already active in another session (they can collide on shared ports and thrash a memory-constrained laptop). Wait for it to finish, then retry. Override: prefix PRESSURE_OVERRIDE=1"
fi
if [ "$class" = "docker" ] && [ "$running" -ge 1 ]; then
  emit deny "⛔ Coordination: a docker build/compose is already active in another session. Machine: $summary. Wait for it, then retry. Override: PRESSURE_OVERRIDE=1"
fi

# 2) pressure gate
if [ "$level" = "RED" ]; then
  emit deny "⛔ RED machine pressure ($summary). Blocking this $class op to avoid a swap-thrash freeze. Free memory first (close idle agent tabs, see the statusline badge), then retry. Override: PRESSURE_OVERRIDE=1"
elif [ "$level" = "AMBER" ]; then
  emit warn "⚠ AMBER machine pressure ($summary); $running $class op(s) already running. Proceeding, but consider closing idle tabs before launching more heavy work."
fi

exit 0
