---
name: task-sync
description: Reconcile your task board so every task's status reflects reality — todo / in-progress / in-review / done — never inflated. Use after merging work, after opening or closing a PR, at session start, or whenever the board feels stale. Triggers: "reconcile my tasks", "clean up the task board", "fix task statuses", "sync tasks", "task cleanup", "are my tasks correct".
---

# task-sync

Keeps your task board honest as a side effect of working, instead of drifting out of sync until someone audits it by hand. This skill does not define your task workflow (task-first, PR-links-task, who approves what) — that belongs in your own project docs. This skill is purely **reconciliation**: read every task, figure out where it really stands, set the right status, flag what's unclear.

**This skill is thin, and its value is conditional.** It only does useful work if you have a task board with an API or CLI you can query and update programmatically ({task-board} below — Jira, Linear, an internal portal, GitHub Projects, whatever tracks your work items). If you don't have one, or your board has no API, skip this skill; there's nothing to reconcile against.

## The status rules

Apply these precisely — they're stricter than "just pick something that sounds right":

| Status | Set it ONLY when… |
|---|---|
| `todo` | Created but **not touched** by you — not started, not reviewed, not approved, not merged. Includes items someone else assigned to you that you haven't begun. Don't auto-bump an assigned-but-unstarted item to `in_progress`. |
| `in_progress` | You are **actively working on it right now**, this session. Nothing else. Not "it's mine and open" — only the one thing currently under your hands. If you're not actively coding it this moment, it is NOT `in_progress`. |
| `in_review` | Work is **ready and waiting**: PR open awaiting review/merge, sitting in a QA queue, or approved and awaiting the human's merge go. Ready, not active. |
| `paused` | Stopped before completion — record a short note on the task saying exactly what's left, if your board supports notes. |
| `done` | **Merged to `{trunk}`.** If your team treats `{trunk}` as the production-ready, tested bar, reaching it is the completion line — a later promotion to a downstream branch is a deploy step, not a separate done-gate. |

**Golden rule: never inflate.** When unsure between two statuses, pick the *lower* one and flag it. `todo` over `in_progress`; `in_review` over `done`. Guessing high is the failure mode this skill exists to prevent.

## Procedure

1. **List your tasks** via {task-board} (your task system's API or CLI) — scope to yourself by default.

2. **For each task, determine its REAL state.** Don't trust the stored status; cross-reference:
   - Linked PRs and their actual state (`gh pr view <n> --json state,reviewDecision,baseRefName,mergeStateStatus`, or your VCS host's equivalent). Merged into `{trunk}` ⇒ `done`. Open PR ⇒ `in_review`. No PR but a branch with commits ⇒ `in_progress` only if you're on it this session, else `paused`/`todo`.
   - A QA/manual-testing queue file, if you keep one — anything queued or approved-awaiting-merge ⇒ `in_review`.
   - Whether you've touched it at all. Untouched (including items assigned to you by someone else) ⇒ `todo`.

3. **Apply the status rules above**, but only when the real state is **unambiguous**. Update via {task-board}'s status-update call. For each change, state in one line what evidence drove it (e.g. "PR #472 MERGED into `{trunk}` → done").

4. **FLAG, don't guess.** For any task that's multi-scope, has closed/renamed PRs, looks like a duplicate, or whose real state you can't pin down — do NOT change it. List it with what you see and the open question. Never bulk-resolve a multi-scope task.

5. **Report** concisely: what changed (status + one-line evidence each), and what you flagged for a human call. Keep it scannable.

## Optional: sweep for assigned-but-untracked work

If your team also hands out work informally (a message in a channel, a comment, a verbal ask) and expects it to land on the board eventually, sweep those channels for items addressed to you. If a matching task already exists and you haven't started it, leave it (or set) `todo`. If something was assigned with no task yet, create a lightweight one in `todo` — task-first — and note it in your report. Skip this step entirely if your team always creates the task before assigning work.

## Scope guard

- Only **your** tasks by default. Don't touch someone else's tasks or enumerate unrelated open PRs unless explicitly asked to audit the whole board.
- This is read-mostly: status writes only on unambiguous evidence; everything uncertain is flagged, not mutated.
- Write task content in plain, self-contained language — no internal codes, doc filenames, or references a first-time reader can't resolve.

## When it runs automatically

Wire this in wherever status can go stale silently:
- **Session start** — a thin nudge reminding you the board may be stale.
- **On merge to `{trunk}`** — whatever flips a merged PR's linked task to `done` should also run this skill's reconciliation as a self-heal, in case that step was ever skipped.
