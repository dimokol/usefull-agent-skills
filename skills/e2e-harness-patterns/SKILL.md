---
name: e2e-harness-patterns
description: Use when designing, evaluating, or extending a local end-to-end test harness — ephemeral multi-service stacks, dynamic ports, seeded fixtures with shared constants, scope-based test selection, session-bypass auth, lock-serialized concurrent runs, dual-speed iteration loops. Pairs with babysit-prs.
---

# e2e-harness-patterns

A reference catalog of patterns that make local end-to-end test harnesses fast, reproducible, and parallel-safe. The patterns are framework-agnostic — Playwright, Cypress, Selenium, custom HTTP-driven harnesses all benefit — but they're most often applied in a Node + Docker context.

This skill is a *reference*: read the pattern(s) that apply to your situation, then design your own harness against them. The companion skill `babysit-prs` consumes the output of a well-designed e2e harness when it gates PR merges on local e2e green.

## When to use this skill

- You're starting a new e2e harness and want to avoid common foot-guns.
- You have an existing e2e harness that's flaky / slow / collides with the user's dev server and you're auditing it for fixes.
- You're considering whether to run e2e in CI vs. locally and want the trade-offs.
- You're integrating a harness with `babysit-prs` and need the patterns it expects.

## When NOT to use this skill

- You need *integration* tests against an in-memory database (single-process, no docker, no browser). That's a different problem; this skill is overkill.
- You're choosing a test runner (Playwright vs. Cypress vs. WebdriverIO). This skill is downstream of that choice.
- You're writing individual specs. That's the job of your runner's own docs.

---

## Pattern 1 — Ephemeral multi-service stack with dynamic ports

**Problem.** An e2e suite needs your app stack running. If you run it against your dev server, every test mutates the dev DB and breaks the next manual click. If you run it against a "permanent test stack" bound to fixed ports, two engineers can never run it simultaneously, and a stale process on a port silently fails the suite.

**Pattern.** Boot the full stack (app + dependencies — DB, cache, queue, etc.) per test invocation, on dynamically allocated host ports. The harness wrapper:

1. Picks free ports by probing (or defers to Docker's `published: 0` and reads back the assigned port).
2. Writes the chosen ports into the test environment via env vars (`E2E_API_URL`, `E2E_APP_URL`).
3. Boots services with health-check gates between them (DB ready before API starts; API responds to `/health` before tests start).
4. Runs the spec set.
5. Tears down — `docker compose down -v` (or equivalent) drops the anonymous volumes.
6. Optional: prunes old build cache opportunistically (e.g. on `EXIT` with a `PRUNE_ON_EXIT=1` flag), trading ~minutes of cold-boot on the next run for reclaimed disk.

The cost is ~30–90 seconds of boot per invocation. The benefits are: reproducibility (every run starts from a known state), portability (no global state to manage), and concurrency (multiple harness instances coexist on the same machine).

**Anti-patterns to avoid.** Don't share the dev server's DB ("just be careful with the seeds" never holds). Don't hard-code ports unless your team is small enough that "I'll yell on Slack first" works. Don't skip the health-check gates — without them you get flakes that look like product bugs but are really "API answered before DB was ready."

## Pattern 2 — Scope-based test selection via `@covers` annotation + import graph union

**Problem.** A test suite that grows past ~30 minutes is run only as a merge gate, never during inner-loop iteration — which means bugs surface days late. But a full run on every push is wasteful when only one spec is relevant to the diff.

**Pattern.** Compute the "affected spec set" as the union of three sources:

1. **Specs directly modified in the diff.** Trivial: `git diff --name-only` filtered to `*.spec.*`.
2. **Specs reached via import graph** from any modified non-test file. Playwright supports this via `--only-changed`; other runners need an equivalent (parse imports, walk the DAG).
3. **Specs annotated with `// @covers <glob>`** matching any modified file. A spec at the top declares the source paths it exercises:
   ```
   // @covers components/booking-form/**
   // @covers lib/queries/bookings.ts
   ```
   When any matching path is in the diff, the spec is in scope. This catches cases (1) and (2) miss: a spec that calls a GraphQL endpoint without statically importing the resolver file; a spec that exercises a generated artifact whose source isn't in the import graph.

**Wire it together.** Your `npm run test:e2e:affected` (or equivalent) runs the union; `:full` runs all specs.

**What to do when the affected runner reports "no specs matched."** Three cases:
- The diff is documentation / copy / no behavior change → genuinely no specs needed. Fine.
- The diff is a refactor whose import graph is intact → existing specs still cover it; their previous green is the gate, no re-run needed. Fine.
- The diff changes product behavior in a way no existing spec covers → write a new spec before merging, or add `@covers` to an existing spec.

The third case is the signal `@covers` is designed to surface. Don't ignore it.

**Anti-patterns to avoid.** Don't run a single spec by name from a debugger and call that "affected coverage" — debugger-driven runs skip the harness's wrapper concerns (env vars, seed, teardown) and don't prove the suite is green. Don't add `@covers **` to a spec to "be safe" — it defeats the affected runner.

## Pattern 3 — Seeded test data with shared fixture constants

**Problem.** Specs hardcode IDs ("the test user is `5f3e4a...`"). The seed script changes; specs break; nobody knows which spec broke first; rebuild takes a day.

**Pattern.** The seed script defines IDs as constants. The test side imports those same constants from a fixture module. Specs never reference an ID by literal — only by name.

Concretely: a `seed-test-fixtures.ts` script seeds users, organizations, sample records, etc., with predictable IDs (e.g. `00000000-0000-0000-0000-00000000000A` — a counter you control, not random). A `fixtures/seed-constants.ts` (or similar) re-exports those same IDs as named constants:

```
export const USER_ADMIN_ID  = '00000000-0000-0000-0000-00000000000A';
export const USER_VIEWER_ID = '00000000-0000-0000-0000-00000000000B';
export const ORG_PRIMARY_ID = '00000000-0000-0000-0000-00000000000C';
```

Specs import the names: `import { USER_ADMIN_ID } from '../fixtures/seed-constants'`.

**Why this matters.** When the seed changes, you change the constants file once. Every spec that depended on the renamed/removed entity surfaces as a TypeScript error or a clear test failure — not a flake. Mutating specs (specs that create / update / delete data) can also generate IDs in a known pattern (`E2E-RUN-<spec-name>-<n>`) that doesn't collide with the seeded base.

**Anti-patterns to avoid.** Don't hardcode IDs inline in specs — the second spec that needs the same entity will diverge silently. Don't seed via the API at the start of each spec ("more realistic, hits the same endpoints") — it inflates spec runtime and couples specs to API stability.

## Pattern 4 — Session-bypass auth via storage priming

**Problem.** Every spec begins with a login flow. Five seconds × 50 specs = 4 minutes of pure auth. Worse, the login flow is itself slow + flaky + occasionally requires email/OTP/MFA that's hard to automate.

**Pattern.** Pre-compute a valid session shape (matching what your auth issues after a real login — a token, user object, expiry timestamp, whatever) and inject it into the browser's storage (`localStorage`, `sessionStorage`, cookies) *before* the first navigation. The app sees a logged-in user from the first paint; no login UI is rendered.

Concretely, in Playwright:

```
test.use({
  storageState: { /* seeded session */ },
});
```

Or via `page.context().addInitScript()` to inject before any page load.

**Trade-offs to understand and document.** This bypass works because the production auth path also reads its session from the same storage location. That means:

- **Pros:** Drastically faster. Drops a fragile dependency on the login UI. Multiple test users can be primed in parallel (one spec runs as `USER_ADMIN_ID`, another as `USER_VIEWER_ID`, no contention).
- **Cons:** The login flow itself is untested. **Have at least one spec that exercises the real login UI** — it's the only thing this pattern *can't* cover. Treat it as a smoke test.
- **When NOT to use:** Specs that explicitly test the login flow, MFA, password reset, etc. Those need the real UI.

**Anti-patterns to avoid.** Don't synthesize JWTs by signing them yourself with the production secret — leak the secret into the test repo and you've leaked auth for prod. Either issue test-only tokens via a dedicated test-issuer endpoint, or use a fixture stored in the seed.

## Pattern 5 — Lock-serialized concurrent runs

**Problem.** Specs run in parallel (default for most modern runners). Two specs mutate the same row in the test DB at the same time. One sees the other's change. Flake.

**Pattern.** There are three valid approaches:

1. **Dedicated "lockdown" entities per spec.** Each spec gets its own seeded entity (`USER_LOCKDOWN_A`, `USER_LOCKDOWN_B`, `BOOKING_LOCKDOWN_FOO`). No two specs touch the same one. Works when spec count is bounded and predictable.
2. **Filesystem-lock serialization for the parallel subset.** Specs that mutate shared state acquire a named lock (`mkdir /tmp/e2e-lock-<resource>` is atomic and portable) before running, release after. Specs without shared state run fully parallel. Compromise: not all-parallel, not all-serial.
3. **Disable parallelism entirely** (`workers: 1` in Playwright config). Simplest, slowest. Acceptable when total suite runtime is under a few minutes.

Pick the simplest that works for your suite size:

- Suite < 5 minutes total, fewer than ~20 specs: option 3 is fine.
- Suite grows past 5 minutes or 50+ specs: option 1 or 2.
- Most teams end up with a mix: option 3 for the suite, option 1 for the most mutation-heavy specs.

**Anti-patterns to avoid.** Don't add `await page.waitForTimeout(500)` "to let the other spec finish" — that's not synchronization, it's wishful thinking. Don't reset the DB between specs by re-running the seed — adds tens of seconds per spec; use isolated entities instead.

## Pattern 6 — Dual-speed iteration

**Problem.** "Affected-only" run is the inner-loop tool; "full suite" run is the merge gate. But every harness invocation re-boots the stack, which dominates runtime when the spec set is small.

**Pattern.** Three variants of the harness command:

- `<run>:affected` — pick specs by scope (Pattern 2), boot stack, run them, tear down. Default for inner loop.
- `<run>:full` — run every spec; merge gate. Less frequent.
- `<run>:nostack` — run against an *already-booted* stack. Use with `KEEP_STACK=1 <run>:affected` to keep the stack hot between iterations:
  ```
  KEEP_STACK=1 npm run e2e:affected    # boots stack, runs affected, leaves stack up
  npm run e2e:nostack -- spec-name     # ~10s instead of ~90s
  ```

When you `KEEP_STACK=1`, the stack does NOT auto-tear-down. Either remember to tear it down manually (`npm run e2e:stop`) or accept that it'll be reaped next time you boot a fresh stack.

**Anti-patterns to avoid.** Don't conflate "speed up" with "skip teardown" — a stack left running for hours accumulates state that contradicts the seed; specs that were green at boot become flaky after a few hours of warm runs. Restart periodically.

---

## Integration with babysit-prs

The `babysit-prs` skill runs a project's e2e suite as Step 4 (for repos where the CLAUDE.md repo map declares `Has local e2e suite? = true`). It expects:

- An e2e command that boots its own stack, runs, and tears down — so the babysit subagent doesn't have to know your stack layout.
- An `:affected` variant (Pattern 2) — babysit prefers affected-only runs and falls back to `:full` only on explicit request.
- A filesystem lock around the stack-boot step — babysit serializes its own per-PR runs to avoid a port collision storm when N PRs babysit in parallel.

A harness designed with the patterns above satisfies all three.

---

## Quick checklist when designing a new harness

- [ ] Stack boots ephemerally per invocation; teardown is reliable.
- [ ] Ports are dynamic or at least explicitly documented + collision-checked.
- [ ] Health checks gate service-to-service startup; no `sleep 5` hacks.
- [ ] Seed script + shared-constants module; no inline IDs in specs.
- [ ] Auth bypass via storage priming, plus ≥1 real-login smoke spec.
- [ ] Affected-only command (`@covers` + import-graph union) and full-suite command both exist.
- [ ] Parallelism strategy chosen explicitly (none / lockdown entities / fs lock) and documented in the harness README.
- [ ] `KEEP_STACK` env knob for inner-loop iteration speed.
- [ ] Teardown prunes anonymous volumes; optional `PRUNE_ON_EXIT` for build cache.

If you check most of these, the harness is in shape for `babysit-prs` to use.
