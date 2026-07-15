# 🪝 Hooks

Guardrail PreToolUse hooks that block risky agent actions.

| Hook | What it solves | Portability |
|---|---|---|
| [no-auto-merge](no-auto-merge/) | Blocks `gh pr merge` / push-to-main unless you opt in per merge. Stops an agent merging on its own. | 🟢 |
| [pr-task-link-guard](pr-task-link-guard/) | Blocks opening a PR that is not linked to a task both ways. Enforces task-first discipline. | 🟡 |
| [worktree-qa-guard](worktree-qa-guard/) | Blocks swapping the main checkout's branch while it is locked for manual QA. Pairs with worktree-qa-queue. | 🟡 |
