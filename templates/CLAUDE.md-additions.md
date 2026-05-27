# CLAUDE.md additions — `babysit-prs` configuration

Paste the block below into your project's `CLAUDE.md` and fill in the placeholders. The `babysit-prs` skill reads this section from your project's CLAUDE.md to figure out which repos it's babysitting, where they live, and how to verify their CI gates.

A filled-in fictional example follows the blank template — use it as a reference shape.

---

## Template (paste into your CLAUDE.md and edit)

```markdown
## babysit-prs Configuration

### Repo map

| Key | Path | GitHub repo | Base branch | Gate verification | Has local e2e suite? | E2E command |
|-----|------|-------------|-------------|-------------------|----------------------|-------------|
| `<key>` | `<absolute path>` | `<owner>/<repo>` | `<base-branch>` | `<one-line description of CI>` | `true`/`false` | `<cmd>` or N/A |

`<key>` is a short alias used in the invocation: `/babysit-prs <key>:<pr>`.

### Quality gates

For each repo, describe what `gh pr checks <pr> --watch` will be waiting on:

- `<key>`: <which CI provider, which jobs/checks, what counts as "green">

### E2E setup (only include if any repo has `Has local e2e suite? = true`)

- **Harness command:** `<cmd>` — boots stack, seeds, runs, tears down.
- **Affected variant:** `<cmd>` — scope-based selection, default for inner loop and babysit.
- **Full variant:** `<cmd>` — pre-merge regression gate.
- **Stack:** <ephemeral docker / persistent / etc.> on <port strategy>.
- **Seed script:** `<path>` — extend before adding new specs.
- **Affected-only policy:** default `:affected`; escalate to `:full` only on explicit request or when the affected runner reports "no specs matched" + the diff clearly impacts product behavior.

### Branch + PR conventions

- **Target branch:** `<base-branch>` (typically `main`, sometimes `dev` / `develop`).
- **PR title format:** <optional convention, e.g. `[FEAT-123] short summary`>.
- **Merge strategy:** <merge commit / squash / rebase> — be explicit; `babysit-prs` doesn't merge for you but the convention affects how Copilot threads/links carry forward.

### Reviewer

- **Reviewer GitHub login:** `<login>` — whose PR review + approval babysit collects (e.g. `copilot-pull-request-reviewer` for GitHub Copilot, or a custom reviewer bot/human login). Defaults to `copilot-pull-request-reviewer` if unset.
- **Ask reviewer via chat:** `<none | tool + channel>` — only if the reviewer must be *pinged* to review (e.g. an agent that lives in Slack/Discord/Teams) rather than auto-triggering on PR open. When set, babysit sends ONE message per batch asking the reviewer to review every PR on GitHub and approve there.
- **Auto-merge:** `off | on` (default **off**) — when on, babysit merges each PR into its base once fully production-ready (gates green, reviewer approved, no unresolved `[CRITICAL]`, prerequisites merged). When off, babysit stops at `READY` for a human to merge. `--no-merge` forces off per run.

### Self-review (always)

babysit always self-reviews the diff against this CLAUDE.md **in parallel** with the reviewer and posts findings as a top-level PR comment with the `[CRITICAL] / [WARNING] / [SUGGESTION]` taxonomy. `[CRITICAL]`/`[WARNING]` are implemented as new commits; `[SUGGESTION]` is folded into the PR by default (deferred only for big expansions or changes that could break the fix). Self-review is the primary signal when the reviewer is slow or never arrives — never merge blind.

If your team has additional self-review rules, add them here.
```

---

## Filled-in example

A fictional 3-repo SaaS monorepo, for shape reference:

```markdown
## babysit-prs Configuration

### Repo map

| Key | Path | GitHub repo | Base branch | Gate verification | Has local e2e suite? | E2E command |
|-----|------|-------------|-------------|-------------------|----------------------|-------------|
| `api`    | `~/projects/example/api-backend`     | `example/api-backend`     | `main` | GitHub Actions (lint + typecheck + jest)        | `false` | N/A                          |
| `admin`  | `~/projects/example/admin-frontend`  | `example/admin-frontend`  | `main` | Vercel preview deployment                       | `true`  | `npm run test:e2e:affected`  |
| `portal` | `~/projects/example/customer-portal` | `example/customer-portal` | `main` | GitHub Actions (lint + build)                   | `false` | N/A                          |

`<key>` is used in the invocation: `/babysit-prs api:412 admin:188 portal:99`.

### Quality gates

- `api`:    GitHub Actions runs `lint`, `typecheck`, `test`. `gh pr checks <pr> --watch` returns when all three complete.
- `admin`:  Vercel deploys a preview per push; the deployment status (`READY` / `ERROR`) is the gate. Pre-commit husky enforces `lint + build` locally, so anything pushed has already passed those.
- `portal`: GitHub Actions runs `lint` and `build`. Same wait semantics as `api`.

### E2E setup

- **Harness command (admin only):** `npm run test:e2e:affected` boots an ephemeral Docker compose stack with auto-selected host ports.
- **Affected variant:** `npm run test:e2e:affected` (default for inner loop and babysit).
- **Full variant:** `npm run test:e2e:full` (pre-merge regression gate).
- **Iterating with hot stack:** `E2E_KEEP_STACK=1 npm run test:e2e:affected` followed by `npm run test:e2e:affected:nostack` for sub-loop runs against the already-booted stack.
- **Seed script:** `scripts/seed-test-fixtures.ts` — extend before adding new specs. IDs use predictable counters; constants surface via `playwright/fixtures/seed-constants.ts`.
- **Affected-only policy:** default `:affected`. Escalate to `:full` only when the affected runner reports "no specs matched" while the diff clearly impacts product behavior, or when explicitly requested.

### Branch + PR conventions

- **Target branch:** `main`.
- **PR title format:** none enforced.
- **Merge strategy:** "Create a merge commit" — preserves PR grouping in `git log` and `git blame`. Squash is acceptable for tiny single-commit cleanups; never use rebase merge.

### Reviewer

- **Reviewer GitHub login:** `copilot-pull-request-reviewer` (GitHub Copilot auto-reviews on PR open).
- **Ask reviewer via chat:** none — Copilot auto-triggers, so babysit just polls for it.
- **Auto-merge:** off — babysit reports `READY`; a human approves + merges.

### Self-review (always)

babysit always self-reviews the diff against this CLAUDE.md in parallel with Copilot and posts findings before merge. `[CRITICAL]`/`[WARNING]` get implemented as new commits; `[SUGGESTION]` is folded into the PR unless it's a big expansion. Never merge blind on a missing/erroring reviewer.
```

---

## Notes for adopters

- The repo map columns are **required** as named — the skill parses them by name, not by position.
- `Base branch` doesn't have to be `main`. Many teams use `dev` or `develop`; the skill reads whatever you write.
- `Has local e2e suite?` flips Step 4 of the skill on/off per repo. If no repo has e2e, the whole step is skipped.
- The `E2E setup` section is read by the skill only loosely (it primarily uses `E2E command` from the map). Most of the content is there for *humans* reviewing what the skill will do — keep it accurate so a teammate or future-you knows the contract.
- The `Reviewer` section drives who babysit collects reviews from, whether it pings them in chat, and whether it auto-merges. Leave `Ask reviewer via chat: none` + `Auto-merge: off` for the simplest setup (Copilot auto-reviews; you merge).
- `Self-review (always)` runs in parallel on every PR — it is no longer just a fallback. The skill follows any extra rules you write here on top of its built-in [CRITICAL]/[WARNING]/[SUGGESTION] flow.
- `Auto-merge: on` is powerful — babysit will merge into the base branch once gates are green and the reviewer has approved. Keep it `off` until you trust the flow; `--no-merge` disables it for a single run.
