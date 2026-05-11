---
name: verify-manual-tests
description: DEPRECATED — superseded by deterministic Playwright e2e specs run via `npm run test:e2e:*`. See README for migration notes.
---

# verify-manual-tests — DEPRECATED

This skill is **deprecated** and no longer maintained.

## Why

The original premise was: prose-checklist "Manual Testing" items in a PR body, executed by an LLM-in-loop driving Playwright MCP against the live dev server. That mechanism only existed because we didn't have deterministic specs. Once you can write a Playwright spec and run it with `npx playwright test`, there is no reason for an LLM to drive the browser — the spec is the test.

## What replaced it

Two ordinary `npm` commands, no skill required:

```bash
# Iteration gate — scoped to changed files
npm run test:e2e:affected

# Pre-merge regression gate — full suite
npm run test:e2e:full
```

Both run an ephemeral docker stack (mongo + backend + frontend) seeded with a known dataset, then drive the FE via Playwright. Specs declare `// @covers <glob>` headers so an affected-runner can pick the right ones. The agent reads the output and acts on failures the same way it reads `npm test` output.

That's the whole replacement: **two commands**. No skill layer needed for "run the tests, read the output, fix what's broken" — that's just normal agent behavior.

## Caveat — these skills were written for Ridebly's workflow

This whole repo (`usefull-agent-skills`) was developed against the Ridebly monorepo. The harness commands, port numbers (`3100`/`4100`), seed-fixture conventions, and PR-template assumptions are specific to that project. Anyone reusing this material elsewhere should:

- Substitute the harness command for whatever your repo uses (Cypress, Playwright with a different bootstrap, etc.).
- Adjust port numbers, base-branch names (`dev`), and any path conventions.
- Re-author the `// @covers` glob convention (or drop it if you don't need scoped runs).

The README's `babysit-prs` section calls out the specific points to edit.

## If you're looking at git history

Earlier revisions of this file documented an LLM-driven Playwright-MCP runner with auto-seed fallbacks, OTP fetching from MongoDB, console/network failure-capture trios, and per-checkbox bug-fix retries. That whole apparatus was retired when the harness moved to deterministic specs. Don't reintroduce it.
