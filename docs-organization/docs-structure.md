# docs/ structure

A convention for organizing a project's `docs/` folder so specs, plans, and
handoffs each have one obvious home. The goal is that any agent or teammate
can find "where does this kind of doc live" without asking.

## The three folders

```
docs/
├── specs/       # what to build, before you build it
├── plans/       # how to build it, step by step
└── handoffs/    # resume docs for unfinished work
    ├── handed/          # picked up (in progress, or done and archived)
    └── not-yet-handed/  # written but nobody has picked it up yet
```

### `docs/specs/`

The WHAT and WHY of a piece of work: intent, scope, constraints, open
questions. Written before code, so a reviewer (human or agent) can sanity
check the plan before anything gets built.

### `docs/plans/`

The HOW: the concrete steps, in order, to implement a spec. Plans reference
their spec rather than repeating it. A plan can be checked off step by step
as work lands, so anyone opening the file mid-implementation sees exactly
how far it got.

### `docs/handoffs/`

Session-to-session resume docs for work that spans more than one sitting.
See `handoff-pattern.md` in this folder for what a handoff should contain.

Handoffs live in one of two subfolders, and the subfolder itself is the
status:

- **`not-yet-handed/`**: written, available, nobody has started it.
- **`handed/`**: picked up. Stays here once finished too, as the
  historical record.

The session that starts the work moves the file from `not-yet-handed/` to
`handed/` as its first step. That way `not-yet-handed/` always reflects
what's genuinely still open, with no need to read every file to check.

## Naming convention

Name docs `YYYY-MM-DD-<topic>.md`, so a directory listing sorts
chronologically and the date tells you at a glance how stale something is.

For handoffs, add a short purpose suffix so the intent is visible without
opening the file:

```
2026-06-03-search-indexing-RESUME.md
2026-06-10-billing-migration-REMAINING.md
2026-06-14-onboarding-flow-AFTER-phase2.md
```

Common suffixes: `-RESUME` (pick up where it left off), `-REMAINING` (what's
left of a larger effort), `-AFTER-<milestone>` (next step once some
precondition lands).

## Commit handoffs, ignore agent scratch

Handoffs are meant to outlive the session that wrote them, so they belong in
git: `git add docs/handoffs/... && git commit`. A handoff nobody can find
after the terminal closes isn't a handoff.

The opposite is true for an agent's own scratch or working directory (temp
notes, intermediate file dumps, working-memory files some agent frameworks
keep alongside a task). That's disposable by nature and floods a diff with
noise no human will ever read. Put it in `.gitignore`:

```gitignore
# agent scratch / working directory - never commit
.agent-scratch/
.superpowers/
```

The rule of thumb: if a future session needs it to resume the work, commit
it under `docs/`. If it's just how the current agent kept track of itself
while working, ignore it.
