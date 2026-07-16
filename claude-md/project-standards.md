# Project engineering standards

Copy-paste blocks for a project's `CLAUDE.md`: performance budgets, readable
code, task and PR discipline, and a reuse-first design principle. Pulled
from a real production ruleset and stripped of anything project-specific.
Fill in the bracketed placeholders (page-size numbers, character counts, the
name of your task board) for your own stack.

---

## Performance

### Latency budget

```markdown
## Latency budget

No query, mutation, or endpoint may take longer than `<TARGET_MS>` (a common
choice is ~500ms) to return on production-like data from a heavy-use
account. Faster is always better; the budget is a ceiling, not a target.

Measure the real response time (network panel or backend timing logs), not
a render. A page only counts as fast when every request it fires is under
budget - one slow query makes the whole page feel slow.

When a query is over budget, look for one of: too many rows fetched, too
many fields fetched, a stat computed in application code instead of the
database, or too many round trips per page. Find the root cause; don't just
add a spinner.
```

### Pagination caps

```markdown
## Pagination caps

Never fetch more than `<DEFAULT_PAGE_SIZE>` (default) / `<MAX_PAGE_SIZE>`
(hard max) list rows in a single query - 20 default / 50 max is a
reasonable starting point. Backend pagination (offset/limit or cursor, plus
a separate count) is mandatory, and the backend must degrade gracefully
when asked for more than the cap: clamp it, don't fail or run out of
memory.

An unbounded list fetch - `limit: 1000`, `limit: 3000`, or no limit at all -
is the standard way an app stops scaling. Treat it as a defect in review,
not a style note.
```

### Backend search, gated at N characters

```markdown
## Backend search, gated at N characters

Never filter or search a fetched list on the frontend; search is always a
backend query with a search argument. Don't fire the query on the first
keystroke - start only once the input reaches `<MIN_SEARCH_CHARS>` (3 is a
reasonable default) characters, and debounce it (300ms is a reasonable
default).

Frontend-only search can only see the rows already loaded, which per the
pagination cap above is small, so it silently fails to find anything outside
the current page. Firing a backend search on every keystroke below the
threshold hammers the database for no benefit.
```

### Stats via database aggregation

```markdown
## Stats via database aggregation

Every statistic - dashboard counters, per-account totals, any stat added in
the future - is computed with a database aggregation pipeline or an
equivalent set-based query. Never fetch rows into application code and
reduce or sum them there.

Aggregation runs in the database, uses indexes, and returns a handful of
numbers instead of transferring thousands of rows to be counted in memory.
Treat a fetch-then-reduce pattern for a count or total as a defect to
replace with a grouped query.
```

---

## Readable code

### Self-documenting code first

```markdown
## Self-documenting code first

Before writing a comment, try to make the comment unnecessary.

- Names carry meaning: a name should say what a value is or a function
  does, not require a comment to explain it.
- Small, single-purpose functions read like a sentence; extract a
  well-named helper instead of leaving a block with a step-by-step comment.
- Let types document shape - a precise type or schema replaces a paragraph
  describing a parameter.
- Early returns over deep nesting keep the happy path flat and readable.
- No magic values: a bare number or string gets a named constant that says
  what it means.
```

### Comment the why, never the what

```markdown
## Comment the why, never the what

Once the code is self-documenting, comments cover only what code can't
express: intent, reasoning, tradeoffs, and gotchas.

Do comment: why a non-obvious choice was made, constraints or gotchas that
aren't visible in the code itself, intent behind logic that isn't clear from
names alone, and links to the source of truth (a ticket, a spec, an
external API quirk).

Don't comment: what the code plainly says, a restatement of the function or
variable name, or commented-out code (delete it; version control remembers
it).

A wrong comment is worse than none. Update or delete a comment in the same
change as the code it describes.
```

### Document public surfaces

```markdown
## Document public surfaces

Exported functions, API handlers, shared hooks or utilities, and any
genuinely complex function get a doc comment - the contract a caller reads
without opening the body.

Required on exported functions/hooks/utilities and anything whose behavior
isn't obvious from its signature. Not required on trivial one-liners or
obvious getters.

Content: a one-line summary of what it does and why you'd call it, plus
parameter/return/throws notes only where the type doesn't already make it
clear. Don't restate types the signature already carries.
```

### Section-mark long files

```markdown
## Section-mark long files

A long file - a large component, module, or handler file - is easier to
scan when its regions are labeled. Use a light, consistent banner comment
to group related code (types, data fetching, handlers, render, and so on).

If a file needs many section markers just to stay navigable, treat that as
a signal to split it. Extraction beats a longer table of contents.
```

---

## Task tracking and PR discipline

### Task-first

```markdown
## Task-first

Before starting any piece of work - feature, fix, refactor, investigation -
check for an existing task on `<TASK_BOARD>`, or create one. Update it
throughout. Work that isn't tracked is work that gets lost or duplicated.

Granularity is per initiative: one task per feature, with multiple PRs
attached to the same task where needed. Small standalone changes still get
a lightweight task, even a one-line one, so there's a record it happened.
```

### Update status on every transition

```markdown
## Update status on every transition

The task status should mirror where the work actually is:

| Status | Means |
|---|---|
| `todo` | created, not started |
| `in_progress` | actively being worked; set this when starting |
| `in_review` | PR open, awaiting review or merge |
| `paused` | stopped before completion - set this whenever pausing, with a note on where things were left |
| `done` | merged and production-ready |

On pause, always record what's left for the next reader. On finishing a
chunk, advance the status and record anything subtle the next reader needs.
```

### PR links its task, both directions

```markdown
## PR links its task, both directions

A PR isn't review-ready until its task is linked both ways:

- The PR body carries the task link (a `## Task` section works well).
- The task board records the PR against the task.

If a PR exists without the link - a fresh one, or one from an earlier
session - patch both directions immediately rather than leaving it
half-linked.
```

---

## Operating principles

### Reuse over duplicate: one source of truth

```markdown
## Reuse over duplicate: one source of truth

Every value or block that repeats across the codebase must come from one
place - a shared constant, token, or component - and be changeable from a
single point. Don't re-declare the same thing per file or per section; this
is the rule that gets broken most, and it's the one that matters most.

Before building or touching something that looks like a repeated pattern:

1. Find the existing constant, token, or component for it and reuse it -
   assume it already exists and search first.
2. If a value will repeat, factor it out up front rather than hardcoding it
   and planning to centralize later. Later rarely comes, and the value
   drifts in the meantime.
3. Match the siblings - a new instance of a pattern should be identical in
   system (naming, spacing, structure) to the ones already shipped.
```

### Ship-it quality bar

```markdown
## Ship-it quality bar

Before calling a visual or user-facing change done, check it against:

- Clarity: a stranger gets the point quickly, without extra explanation.
- Reuse: every repeated value or block comes from a single source.
- Consistent: matches sibling features in spacing, structure, and
  interaction, not just superficially similar.
- Responsive: works cleanly from small screens to wide ones; fluid, not
  just patched at a few breakpoints.
- Accessible: keyboard-operable, respects reduced-motion preferences,
  semantic markup, sufficient contrast.
- Performant: no janky interaction; heavy assets are gated or lazy-loaded.
- On-brand: matches the established palette, type, and voice.
- Verified visually: actually looked at, at more than one viewport, not
  just typechecked and shipped.
```
