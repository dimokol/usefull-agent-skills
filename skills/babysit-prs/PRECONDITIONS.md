# babysit-prs — Preconditions

What your project needs in order for `babysit-prs` to do useful work. Read this once before adopting the skill; you'll only adopt about half of what's described, depending on which repos you babysit.

This document complements `SKILL.md` (which describes the procedure) with the assumptions that procedure makes about your environment.

---

## Hard preconditions (skill cannot work without these)

1. **GitHub-hosted repos.** The skill drives the `gh` CLI and the GitHub REST + GraphQL APIs. GitLab, Bitbucket, self-hosted Gitea, etc. are not supported out of the box.
2. **`gh` CLI installed and authenticated.** `gh auth status` should show an authenticated user with access to every repo listed in your CLAUDE.md repo map. Token needs `repo` + `read:org` scope (the default for personal access tokens via `gh auth login` is fine).
3. **PR-based workflow.** The skill assumes work lands on a base branch (commonly `main`, sometimes `dev`, `develop`, `master`, etc.) via pull requests, not direct pushes. Each repo's base branch is declared in the CLAUDE.md repo map.
4. **Branch protection on the base branch.** This is what makes "review + CI pass" meaningful. Without protection, the skill still runs, but its "merge-ready" signal is weaker than it appears — anyone could bypass it anyway.
5. **Some form of CI that `gh pr checks --watch` can observe.** GitHub Actions, Vercel preview deployments, CircleCI, etc. — anything that posts checks/statuses against the PR's HEAD SHA. The skill never executes your CI itself; it just waits for and reads the result.
6. **`git` ≥ 2.5 with worktree support.** The skill isolates each PR in a sibling worktree (`<repo-path>--babysit-pr-<n>`). This has been default in `git` since 2015; on macOS Monolith this means "any reasonably current Homebrew or Xcode-CLT install."
7. **At least 10 GB free on the host disk.** The skill's Step 0 disk gate refuses to start below this threshold because a Docker e2e harness can ENOSPC mid-build and leave stale locks + lost work behind. If you have no e2e harness, the gate is conservative but not harmful.

## Soft preconditions (skill adapts when absent)

- **A configured code reviewer.** Set `Reviewer GitHub login` in your CLAUDE.md to whoever reviews PRs — GitHub Copilot (`copilot-pull-request-reviewer`), a custom bot, or a human. The skill collects that login's review + approval in Step 4. If the reviewer must be *pinged* (an agent that lives in a chat tool) rather than auto-triggering on PR open, set `Ask reviewer via chat`. Regardless, the skill **always self-reviews in parallel** (Step 1), so a missing / erroring / slow reviewer never blocks progress.
- **Local end-to-end test suite.** If a repo's row in your CLAUDE.md has `Has local e2e suite? = true`, the skill runs `<e2eCmd>` from the worktree (Step 4). If no repo has e2e, Step 4 is skipped entirely. Recommended for projects whose e2e cost makes CI-runs prohibitive but local-runs feasible — see the companion skill `e2e-harness-patterns`.
- **Pre-commit hooks (husky / lefthook / pre-commit).** If your project enforces lint/format/typecheck pre-commit, the skill trusts that anything pushed has already passed — and skips local re-runs in Step 3. If there's no pre-commit gate, the skill still works; CI catches the same errors a few seconds later.
- **Extra self-review rules.** The skill always self-reviews (Step 1: read the diff against CLAUDE.md, post findings) — that's built in and runs in parallel with the reviewer, not just as a fallback. If your team has additional review rules, write them into your CLAUDE.md and the skill follows them on top of its built-in [CRITICAL]/[WARNING]/[SUGGESTION] flow.
- **Auto-merge.** Off by default — the skill stops at `READY` and you merge. Turn it on (in your CLAUDE.md `Reviewer` config) only once you trust the flow; then the skill merges each PR into its base after gates are green and the reviewer has approved. `--no-merge` disables it for one run.

---

## What your CLAUDE.md must provide

Copy `templates/CLAUDE.md-additions.md` from this repo into your project's `CLAUDE.md` and fill in the placeholders. At minimum the skill needs:

- **A repo map** — one row per repo, with: short key, absolute path, GitHub `owner/repo`, base branch, how to verify CI, whether local e2e applies, e2e command if so.
- **A quality-gates note** — which CI handles what (lint? typecheck? build? unit tests?). The skill never re-runs these locally; it waits for CI to report.
- **An e2e setup note** (only if any repo has e2e) — harness command, stack ports/dynamic-port behavior, seed-script path, affected-only policy.
- **Branch + PR conventions** — base branch name, PR title format if any, merge strategy.

Without that section in your CLAUDE.md, the calling session has nothing to read; it will refuse to start (or worse, guess).

---

## Concrete example (fictional 3-repo monorepo)

Suppose you maintain a SaaS product in three repos under `example/`:

- `example/api-backend` — Node + Postgres, GitHub Actions CI runs lint + typecheck + jest. Base branch: `main`.
- `example/admin-frontend` — Next.js, Vercel deploys preview per push (preview build = the gate). Local Playwright e2e suite, NOT in CI by cost choice. Base branch: `main`.
- `example/customer-portal` — Next.js, GitHub Actions CI runs lint + build. Base branch: `main`.

Your project's `CLAUDE.md` would include:

```markdown
## babysit-prs Configuration

### Repo map
| Key | Path | GitHub repo | Base branch | Gate verification | Has local e2e suite? | E2E command |
|-----|------|-------------|-------------|-------------------|----------------------|-------------|
| `api`    | `~/projects/example/api-backend`     | `example/api-backend`     | `main` | GitHub CI (lint + typecheck + jest)  | `false` | N/A                          |
| `admin`  | `~/projects/example/admin-frontend`  | `example/admin-frontend`  | `main` | Vercel preview build                 | `true`  | `npm run test:e2e:affected`  |
| `portal` | `~/projects/example/customer-portal` | `example/customer-portal` | `main` | GitHub CI (lint + build)             | `false` | N/A                          |

### Quality gates
- `api`:    GitHub Actions, jobs `lint`, `typecheck`, `test` — `gh pr checks <pr> --watch` returns when all complete.
- `admin`:  Vercel preview deployment — `gh pr checks <pr> --watch` returns when deployment is `READY` or `ERROR`.
- `portal`: GitHub Actions, jobs `lint`, `build` — `gh pr checks <pr> --watch`.

### E2E setup
- Harness command (admin only): `npm run test:e2e:affected`
- Stack: ephemeral Docker compose on auto-selected host ports.
- Seed script: `scripts/seed-test-fixtures.ts` — extend before adding new specs.
- Affected-only policy: default `:affected`; fall back to `:full` only on user request or "no specs matched + diff clearly impacts product behavior."

### Branch + PR conventions
- Target branch: `main`.
- Merge strategy: merge commit (preserves PR grouping in `git log`).

### Reviewer
- Reviewer GitHub login: `copilot-pull-request-reviewer` (Copilot auto-reviews on PR open).
- Ask reviewer via chat: none. Auto-merge: off (babysit reports READY; you merge).

### Self-review (always)
babysit always self-reviews the diff against this CLAUDE.md in parallel with the reviewer and posts findings (same [CRITICAL]/[WARNING]/[SUGGESTION] taxonomy); [CRITICAL]/[WARNING] get implemented as new commits, [SUGGESTION] folded into the PR unless it's a big expansion. Never merge blind on a missing/erroring reviewer.
```

You'd then invoke the skill like:

```
/babysit-prs api:412 admin:188 portal:99
```

…and three subagents run in parallel, each isolated in its own worktree.

---

## Adopter checklist

Before you invoke `/babysit-prs` for the first time in a new project:

- [ ] Each target repo is GitHub-hosted and `gh auth status` shows you authenticated against them.
- [ ] Branch protection is enabled on each repo's base branch (review required + status checks).
- [ ] You've installed `git` ≥ 2.5 (check: `git --version`). Worktrees enabled by default.
- [ ] Each repo has CI configured such that `gh pr checks <pr> --watch` returns a meaningful pass/fail.
- [ ] If any repo has local e2e: the harness command runs cleanly on a fresh PR branch from a fresh worktree (with `node_modules` symlinked, no `npm install`).
- [ ] Set `Reviewer GitHub login` (e.g. `copilot-pull-request-reviewer`) in your CLAUDE.md. Optional: `Ask reviewer via chat` if the reviewer must be pinged, and `Auto-merge: on` if you want babysit to merge once green + approved. The skill always self-reviews regardless.
- [ ] You've added a `babysit-prs Configuration` section to your project's `CLAUDE.md` per the template above.
- [ ] You've run `df -g /` and have ≥10 GB free.

If any of the above isn't true and the skill bails out, that's an early-warning. The skill is designed to refuse rather than guess.

---

## What this skill does NOT do

For clarity, things that are explicitly out of scope:

- **It does not write your PR.** Open the PR yourself (or let your other agents do it); the skill picks up an *existing* open PR.
- **It does not approve PRs, and merges only when you opt in.** It always takes a PR to "merge-ready" — applies fixes, resolves reviewer threads, runs gates. Approval is the reviewer's; merge is yours unless you set `Auto-merge: on` (then babysit merges into the base once gates are green and the reviewer has approved).
- **It does not handle release PRs differently.** A `dev → main` release PR babysits the same as any feature PR. If your project requires manual coordination on releases, do that yourself.
- **It does not maintain its own state across sessions.** Marker files under `/tmp/babysit-*` enable in-session resume after a crash, but they're ephemeral. A reboot wipes them; the skill re-derives state from GitHub on next invoke.
- **It does not handle non-GitHub review tools.** Reviewable, Phabricator, Gerrit, etc. — not supported.
