#!/bin/sh
# worktree-qa-guard: a Claude Code PreToolUse hook that blocks swapping a
# repo's main-checkout branch while it is locked for manual QA. Pairs with
# the `worktree-qa-queue` skill in this hub: a branch gets promoted into the
# main checkout (not a worktree) for a human to test on a real dev server,
# and a `.qa-lock` file at the repo root marks that checkout OCCUPIED for the
# duration. This hook makes "don't swap the branch out from under the tester"
# a mechanical guarantee instead of a rule someone has to remember.
#
# A checkout is OCCUPIED when `.qa-lock` exists at its repo root (written on
# promotion, removed when the human marks the branch done). While occupied,
# this hook blocks branch-SWAPPING git ops (checkout / switch / reset --hard)
# targeting that checkout. Those are the only ops that change the branch a
# dev server is running from. Read-only git (fetch/log/status/diff/show) and
# every `git worktree` subcommand (add/remove/prune/list, none of which touch
# the main checkout's branch) always pass through, as does any path that
# looks like a worktree (matches `*--wt/*`, `*--wt`, or `*--qa-*`). Dev
# happens there, never in the locked main checkout.
#
# CONFIG (env vars, all optional):
#   ALLOW_QA_CHECKOUT=1   prefix on the command itself: explicit, deliberate
#                          override, set only after the human has freed the
#                          slot or explicitly instructed the swap.

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Explicit override, set only after the human frees the slot / instructs it.
case "$CMD" in *ALLOW_QA_CHECKOUT=1*) exit 0 ;; esac

# Only consider branch-SWAPPING git ops; everything else (incl. ALL `git
# worktree` subcommands, which never change the main checkout's branch) is
# irrelevant.
printf '%s' "$CMD" | grep -qE '\bgit\b([[:space:]]+-C[[:space:]]+[^[:space:]]+)?([[:space:]]+-[^[:space:]]+)*[[:space:]]+(checkout|switch|reset)\b' || exit 0
# A plain `git reset` (soft/mixed) and `git checkout -- <file>` are not branch
# swaps; only gate `reset --hard` and branch-style checkout/switch.
case "$CMD" in
  *"git reset"*) printf '%s' "$CMD" | grep -qE 'reset[[:space:]].*--hard' || case "$CMD" in *checkout*|*switch*) : ;; *) exit 0 ;; esac ;;
esac

# Resolve the directory the git op targets: `git -C <dir>`, else a leading
# `cd <dir> &&`, else the tool cwd, else pwd.
DIR=$(printf '%s' "$CMD" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+"?([^" ]+)"?.*/\1/p')
[ -z "$DIR" ] && DIR=$(printf '%s' "$CMD" | sed -nE 's/^[[:space:]]*cd[[:space:]]+"?([^" &]+)"?[[:space:]]*&&.*/\1/p')
[ -z "$DIR" ] && DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -z "$DIR" ] && DIR=$(pwd)
case "$DIR" in "~"*) DIR="$HOME${DIR#\~}" ;; esac

# Worktree paths are always allowed (dev happens there, never in a locked
# main checkout).
case "$DIR" in *--wt/*|*--wt|*--qa-*) exit 0 ;; esac

# Resolve the repo root so the lock is found regardless of which subdirectory
# the command targeted. Not a git repo (or git missing) → nothing to guard.
ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)
[ -n "$ROOT" ] || exit 0

LOCK="$ROOT/.qa-lock"
[ -f "$LOCK" ] || exit 0   # checkout is FREE → allow

OCCUPANT=$(head -1 "$LOCK" 2>/dev/null)
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: %s is locked for manual QA (branch [%s], see %s and your worktree-qa-queue file). Do NOT swap its branch. A dev server may be running from here. The slot frees only when the human marks that branch done. Work in a WORKTREE instead. If the human has freed the slot or explicitly told you to swap it, re-run prefixed with ALLOW_QA_CHECKOUT=1."}}\n' "$ROOT" "$OCCUPANT" "$LOCK"
exit 0
