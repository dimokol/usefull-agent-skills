---
name: create-pr
description: Open a PR that already follows your project's conventions (PR body template, test-verification markers, task-board linkage, and deploy notes), all configured via your project's CLAUDE.md. Use before every `gh pr create` call or when auditing an existing PR for missing markers. Pairs with `babysit-prs` (shares the `babysit-verified` marker convention).
---

# create-pr

Consolidates your project's PR-creation conventions into one skill, so nothing gets missed between "code is done" and "PR is open."

## When to use

- Before calling `gh pr create` for any repo in your project
- When auditing an existing PR for missing markers (task link, test-verification marker, checkbox state)

## Configuration (provided by your project's CLAUDE.md)

This skill reads its config from your project's `CLAUDE.md`. **Adopters:** copy the `create-pr Configuration` block from `templates/CLAUDE.md-additions.md` in this repo into your project's `CLAUDE.md` and fill in your values.

Your config needs to define:

- **PR body template**: your section names, order, and what goes in each.
- **Test-verification marker**: the machine-readable comment your babysitting/CI flow checks for. If you also use `babysit-prs`, reuse the shared `babysit-verified` marker below so the two skills interoperate for free.
- **Task-link line format**: how a PR references your task board (`{task-board}`), if you use one.
- **Deploy notes**: target trunk (`{trunk}`), cross-repo pairing convention, and your merge policy.

If your project has no config section for this yet, say so and offer to scaffold one from the template rather than guessing at a format.

## PR Body Template (generic shape, replace with your configured template)

```
## Task
<{task-board} link line, e.g. "Task: <url>">
<Omit this section if you don't use a task board.>

## Summary
<1-3 bullets: what changed and what capability it adds>

## Why
<1 sentence: business driver, blocker, or ticket reference>

## Tests
<For backend/API-style PRs:>
- <test suite>: X new tests, Y existing tests pass (regression clean)
<For frontend/e2e-covered PRs:>
- e2e: X/Y affected specs green locally
<!-- babysit-verified: {"e2e":"X/Y","date":"YYYY-MM-DD","sha":"<7-char HEAD SHA>"} -->
<Omit the marker line if the local suite was NOT run in this session.>

## Standards compliance
<Optional: include only if your project has a compliance gate (performance, security, accessibility, or similar) that PRs must self-report against. Reference your own doc; list PASS / N-A(reason) + evidence per rule.>

## Paired with <other repo>
- {repo}: PR #NNN (`branch-name`)
<Omit if standalone.>

## Manual verification
- [ ] <item 1>
- [ ] <item 2>
<Cap at 1-3 items. Only for things genuinely impossible to automate. Omit the section entirely if nothing needs manual checking.>

## Design / Plan
<Omit if no design doc.>
```

---

## Rule 1: test-verification marker (repos with a local e2e/test harness)

When your local e2e suite (or any slow test harness not covered by CI) runs and passes **in the same session** that creates or amends the PR, add a machine-readable marker to the Tests section:

```
<!-- babysit-verified: {"e2e":"X/Y","date":"YYYY-MM-DD","sha":"<7-char HEAD SHA>"} -->
```

Place it on the line immediately after the test-results bullet it verifies.

This marker name and shape are shared with the `babysit-prs` skill. If you use both, stamping it here lets babysit-prs's e2e step skip re-running the harness against the same commit (see `babysit-prs/SKILL.md`, Step 3). If you don't use babysit-prs, the marker still documents when, and against which commit, the tests last ran.

**What this marker does and does NOT do:**
- **Does:** tells a downstream PR-babysitting flow it can skip re-running the local harness for this exact HEAD SHA.
- **Does NOT:** skip self-review, CI gates, `{reviewer}`'s review + approval, the merge gate, or manual-checkbox ticking. Those all still run.

**SHA is mandatory going forward.** A consumer of this marker should validate `sha` against the PR's current HEAD. If new commits were pushed after the tests ran, the SHA won't match and the harness should re-run. Treat a marker without a SHA as legacy, not something to trust blindly.

**Add the marker via:**
```bash
SHA=$(git rev-parse HEAD | head -c 7)
DATE=$(date +%Y-%m-%d)
CURRENT=$(gh pr view <pr> --repo <owner>/<repo> --json body -q '.body')
UPDATED=$(printf '%s' "$CURRENT" | sed "s|- e2e: \([0-9/]*\) affected specs green locally|- e2e: \1 affected specs green locally\n<!-- babysit-verified: {\"e2e\":\"\1\",\"date\":\"$DATE\",\"sha\":\"$SHA\"} -->|")
gh pr edit <pr> --repo <owner>/<repo> --body "$UPDATED"
```

Adjust the `sed` pattern to match your own Tests-section bullet text.

---

## Rule 2: task-board linkage (only if your project uses one)

Skip this rule entirely if your project has no task board.

If you track work items on a board (`{task-board}`, could be Jira, Linear, an internal portal, whatever tracks work items) and your convention is "a task exists before a PR opens," link both directions before the PR goes to review:

1. PR body: add the task-link line in the `## Task` section, per your configured format.
2. Task board: attach the PR number to the task, via whatever API or tool your board provides.

**No task yet? Create one first.** Don't open a PR without one, if that's your project's rule. **Check both directions** on existing PRs too. If a PR already exists without the link, patch it (`gh pr edit` + your task board's link call). This applies to PRs opened in other sessions as well.

---

## Rule 3: deploy notes

State, per your project's config:

- **Target trunk**: which branch (`{trunk}`) this PR merges into. Most repos have one; some route through a staging trunk before a production one.
- **Cross-repo pairing**: if this change is paired with a matching change in another repo (`{repo}`), use the **same branch name** in both and note the pairing explicitly in the PR body ("Paired with `{repo}`: PR #NNN (`branch-name`)"). Omit if the PR is confirmed standalone.
- **Merge policy**: this skill only opens and shapes the PR; it never merges. Follow your project's own merge policy for who or what triggers the actual merge (see your `babysit-prs` config's Auto-merge setting, if you use that skill).

---

## Rule 4: tick manual test-plan checkboxes after tests go green

When your test suite finishes green (locally, or via a babysitting flow reporting ready), tick every `- [ ]` in the "Manual verification" section:

```bash
BODY=$(gh pr view <pr> --repo <owner>/<repo> --json body -q '.body')
gh pr edit <pr> --repo <owner>/<repo> --body "$(printf '%s' "$BODY" | sed 's/- \[ \]/- [x]/g')"
```

Useful if your team treats these checkboxes as a single-glance "is this PR exercised?" signal during merge triage.

---

## Rule 5: additive-contract completeness self-review (before opening)

A recurring cause of multi-round reviews is an additive change wired into one place but missing from its sibling sites. Before opening the PR, and before the first reviewer ping, if the diff ADDS a new enum value, notification key, config field, status, or boolean return, grep the new identifier repo-wide and confirm every sibling site is updated. Two patterns worth checking on their own:

- **A function's return value changed from `void` to a result/boolean** (e.g. a send/dispatch function now reports success or failure). Grep every caller and confirm they actually consume it. A returned-but-ignored result is a silent bug: the caller advances state as if the action succeeded when it didn't.
- **A new dedup/idempotency marker**: confirm it distinguishes "evaluated, nothing to do" (mark done, don't reprocess) from "a real failure" (don't mark done, allow retry).

If your project keeps a list of known sibling sites for additive changes (a shared enum that also needs a schema update, a defaults list, a backfill script), reference that list here in your own CLAUDE.md so this check has something concrete to grep for.

---

## Pre-flight checklist

Before running `gh pr create`:

- [ ] PR body uses your configured template (all sections present or intentionally omitted)
- [ ] Tests section lists actual results (numbers, not "tests pass")
- [ ] Additive change (new key / enum / field / status / boolean) → all sibling sites updated (Rule 5)
- [ ] Local test harness ran in this session → `<!-- babysit-verified: ... -->` marker added, if your project uses one
- [ ] Task board configured and required → task link in PR body + linked on the task board (Rule 2)
- [ ] Standards-compliance section filled, if your project has that gate
- [ ] Paired repo PR referenced, if applicable
- [ ] Manual verification section capped at 1-3 items (or omitted)
- [ ] Target branch is `{trunk}` (not a hotfix-only branch, unless this is one)
