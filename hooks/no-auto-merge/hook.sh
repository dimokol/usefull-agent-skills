#!/bin/sh
# no-auto-merge guard — a Claude Code PreToolUse hook that physically blocks
# merge/deploy commands so an agent can never merge a PR or push to a protected
# branch on its own initiative. The agent runs reviews and gates, then stops and
# reports "ready, awaiting your explicit merge approval".
#
# Override: prefix the specific approved command with ALLOW_MERGE=1.
# The agent should only do that after you explicitly approve that exact merge.
#
# Protected branches: main and master by default. Adjust the patterns below if
# your protected branch is named differently (e.g. add |production).
#
# Install (settings.json):
#   "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [
#     { "type": "command", "command": "sh \"$HOME/.claude/hooks/no-auto-merge.sh\"" }
#   ] } ] }

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Explicit per-merge override, set only after the operator's approval.
case "$CMD" in *ALLOW_MERGE=1*) exit 0 ;; esac

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED by the no-auto-merge guard (%s). Merges and pushes to protected branches require the operator'"'"'s explicit instruction and manual approval. Run reviews/gates, then STOP and report: ready, awaiting explicit merge approval. After approval, re-run prefixed with ALLOW_MERGE=1."}}\n' "$1"
  exit 0
}

# 1) gh pr merge — any repo, any base.
printf '%s' "$CMD" | grep -qE '\bgh[[:space:]]+pr[[:space:]]+merge\b' && deny "gh pr merge"

# 2) gh api merge endpoints (REST PR merge / branch merge, GraphQL merge mutations).
printf '%s' "$CMD" | grep -qE '\bgh[[:space:]]+api\b[^|;&]*(/pulls/[0-9]+/merge|/merges\b)' && deny "gh api merge endpoint"
printf '%s' "$CMD" | grep -qiE 'mergePullRequest|enablePullRequestAutoMerge' && deny "GraphQL PR merge mutation"

# 3) git push with a refspec targeting a protected branch (covers dev:main,
#    HEAD:main, --force). Matches only full destination tokens, so branches
#    like feat/main-page do not false-positive.
printf '%s' "$CMD" | grep -qE '\bgit([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push\b[^|;&]*[[:space:]]([^[:space:]]+:)?(main|master)([[:space:]]|$|[;&|"'"'"'])' && deny "push to protected branch"

# 4) git merge / bare git push while the target repo is checked out on a
#    protected branch.
if printf '%s' "$CMD" | grep -qE '(^|[;&|][[:space:]]*)(command[[:space:]]+)?git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?([[:space:]]+-[^[:space:]]+)*[[:space:]]+(merge|push)([[:space:]]|$)'; then
  DIR=$(printf '%s' "$CMD" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+"?([^" ]+)"?.*/\1/p')
  [ -z "$DIR" ] && DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
  [ -z "$DIR" ] && DIR=$(pwd)
  case "$DIR" in "~"*) DIR="$HOME${DIR#\~}" ;; esac
  BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
  case "$BRANCH" in
    main|master)
      printf '%s' "$CMD" | grep -qE '[[:space:]]merge([[:space:]]|$)' && deny "git merge while on $BRANCH"
      printf '%s' "$CMD" | grep -qE '[[:space:]]push([[:space:]]|$)' && deny "git push while on $BRANCH"
      ;;
  esac
fi

exit 0
