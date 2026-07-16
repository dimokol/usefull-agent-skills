# pr-task-link-guard (PreToolUse hook)

Blocks `gh pr create` when the PR body carries no link to a task-board item. A machine-level guarantee for teams whose rule is "a task exists before a PR opens, and the PR references it", the kind of rule that's easy to forget mid-session and expensive to discover only after a reviewer blocks approval on it.

## Why

Prompt-level rules ("always link the task") are soft: a long session, a compacted context, or an over-eager skill can walk right past them. A `PreToolUse` hook is hard: the command is denied before it runs, and the denial message tells the agent exactly what to do instead.

## What it blocks

`gh pr create` when the resolved PR body (inline `--body` or `--body-file`) does not match the configured task-link pattern.

## What it does NOT block

Everything else: `gh pr view` / `gh pr checks` / `gh pr edit`, all read-only `git`/`gh` commands, and any `gh pr create` whose body already contains a matching task link.

## Configuration

All via environment variables, all optional:

| Variable | Default | Purpose |
|---|---|---|
| `TASK_LINK_PATTERN` | `(Task\|Ticket\|Issue)[[:space:]]*:.*https?://\|https?://[^ ]*/(tasks\|issues)/` | Extended regex (`grep -E`) the PR body must match. Override to match your own {task-board}'s URL shape, e.g. `TASK_LINK_PATTERN='linear\.app/[^ ]+/issue/'`. |
| `PR_TASK_LINK_SCOPE` | unset | Colon-separated list of substrings. When set, the gate only applies if the PR's `--repo` value or the command's working directory contains one of them. Unset (default) applies to every `gh pr create`. |
| `ALLOW_UNLINKED_PR=1` | N/A | Prefix on the command itself: explicit, deliberate opt-out for a genuinely task-less PR (pure CI/config). |

## Install

1. Copy the script somewhere stable and make it executable:

   ```bash
   mkdir -p ~/.claude/hooks
   curl -fsSL https://raw.githubusercontent.com/dimokol/usefull-agent-skills/main/hooks/pr-task-link-guard/hook.sh \
     -o ~/.claude/hooks/pr-task-link-guard.sh
   chmod +x ~/.claude/hooks/pr-task-link-guard.sh
   ```

2. Register it in `~/.claude/settings.json` (merge with your existing hooks):

   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             { "type": "command", "command": "sh \"$HOME/.claude/hooks/pr-task-link-guard.sh\"" }
           ]
         }
       ]
     }
   }
   ```

3. If your task-board URL doesn't match the default pattern, set `TASK_LINK_PATTERN` (and optionally `PR_TASK_LINK_SCOPE`) in the same env block, or export them in your shell profile.

4. Add the matching policy to your project's CLAUDE.md so the agent knows the rule rather than just hitting the wall. See the `create-pr` skill's "task-board linkage" rule for a template.

5. Verify: ask the agent to run `gh pr create --title x --body "no task here"` (dry). It should be denied with the guard's message, while a body containing `Task: https://example.com/tasks/123` passes.

Requires `jq`.
