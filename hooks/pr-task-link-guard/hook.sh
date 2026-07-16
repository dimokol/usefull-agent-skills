#!/bin/sh
# pr-task-link-guard: a Claude Code PreToolUse hook that blocks `gh pr create`
# when the PR body carries no link to a task-board item. Enforces "a task
# exists before a PR opens, and the PR references it" mechanically instead of
# hoping the agent remembers the prose rule every time.
#
# CONFIG (env vars, all optional):
#   TASK_LINK_PATTERN     extended-regex (grep -E) the PR body must match.
#                          Default matches a "Task:"/"Ticket:"/"Issue:" label
#                          followed by a URL, or a bare link into a /tasks/
#                          or /issues/ path. Override to match your own
#                          {task-board}'s URL shape, e.g.:
#                            TASK_LINK_PATTERN='linear\.app/[^ ]+/issue/'
#   PR_TASK_LINK_SCOPE    colon-separated list of substrings; when set, the
#                          gate only applies if the PR's --repo value or the
#                          command's working directory contains one of them.
#                          Unset (default) = applies to every `gh pr create`.
#   ALLOW_UNLINKED_PR=1   prefix on the command itself: explicit, deliberate
#                          opt-out for a genuinely task-less PR (pure CI/config).
#
# Install (settings.json):
#   "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [
#     { "type": "command", "command": "sh \"$HOME/.claude/hooks/pr-task-link-guard.sh\"" }
#   ] } ] }

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Only act on `gh pr create`.
printf '%s' "$CMD" | grep -qE '\bgh[[:space:]]+pr[[:space:]]+create\b' || exit 0

# Explicit deliberate override for task-less PRs.
case "$CMD" in *ALLOW_UNLINKED_PR=1*) exit 0 ;; esac

# Optional scope gate: only apply where the operator opted in.
if [ -n "$PR_TASK_LINK_SCOPE" ]; then
  REPO_ARG=$(printf '%s' "$CMD" | sed -nE 's/.*--repo[[:space:]]+"?([^" ]+)"?.*/\1/p')
  SCOPE_DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
  in_scope=0
  OLD_IFS=$IFS
  IFS=':'
  for part in $PR_TASK_LINK_SCOPE; do
    [ -z "$part" ] && continue
    case "$REPO_ARG" in *"$part"*) in_scope=1 ;; esac
    case "$SCOPE_DIR" in *"$part"*) in_scope=1 ;; esac
  done
  IFS=$OLD_IFS
  [ "$in_scope" = 1 ] || exit 0
fi

# Resolve the PR body text: inline --body "..." or --body-file <path>.
BODY=""
BODYFILE=$(printf '%s' "$CMD" | sed -nE 's/.*--body-file[[:space:]]+"?([^" ]+)"?.*/\1/p')
if [ -n "$BODYFILE" ]; then
  case "$BODYFILE" in "~"*) BODYFILE="$HOME${BODYFILE#\~}" ;; esac
  [ -f "$BODYFILE" ] && BODY=$(cat "$BODYFILE" 2>/dev/null)
else
  # inline --body: grab everything (best-effort; the check below is substring-based).
  BODY="$CMD"
fi

DEFAULT_PATTERN='(Task|Ticket|Issue)[[:space:]]*:.*https?://|https?://[^ ]*/(tasks|issues)/'
PATTERN="${TASK_LINK_PATTERN:-$DEFAULT_PATTERN}"

# Pass if the body carries a task-board link matching the configured pattern.
printf '%s' "$BODY" | grep -qiE "$PATTERN" && exit 0

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: this PR has no task-board link in its body. Fix first: create or find the task on {task-board}, add a line referencing it to the PR body (e.g. \\"Task: <url>\\"), link the PR back to the task via your task board'"'"'s API, THEN re-run gh pr create. Genuinely task-less PR (pure CI/config)? prefix ALLOW_UNLINKED_PR=1."}}\n'
exit 0
