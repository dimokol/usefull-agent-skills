# Agent memory: a file-based system that survives across sessions

> Read this before setting up persistent memory for an agent, or before deciding whether a
> new fact belongs in memory at all. The second question matters more than the schema.

An agent that starts every session with a blank slate re-learns the same lessons over and
over. A `memory/` folder fixes that: a small set of files the agent reads at the start of
every session, so a correction you made three weeks ago still applies today.

Plain markdown files, checked into a location the agent loads automatically, small enough
to read in full each time. Nothing to run, nothing to configure.

---

## Layout

```
memory/
  MEMORY.md              # the always-loaded index
  some-lesson.md          # one fact
  another-lesson.md        # one fact
  a-project-fact.md        # one fact
```

One index, one fact per file. A file holds a single fact, not a running log. When a fact
changes, edit the file in place; when it stops being true, delete it and remove its line
from the index. This keeps each file small enough to skim and small enough that a diff on
it is meaningful.

## Frontmatter schema

Each fact file opens with frontmatter:

```markdown
---
name: some-lesson
description: One line, used to judge whether this file is relevant right now.
metadata:
  type: feedback
  source_session: 2026-04-11-session-abc123   # optional, provenance
---

One-line fact.

**Why:** the incident that earned this lesson.

**How to apply:** what to do differently next time.

See also [[another-lesson]].
```

- **`name`** is the kebab-case slug, matching the filename.
- **`description`** is a one-line summary used purely for recall relevance: when an agent
  or a human is scanning the index for something applicable, this line is what they judge
  against.
- **`metadata.type`** is one of the four types below. It's the field that decides how much
  weight the fact carries and how it should be pruned.
- **`source_session`** (optional) is provenance: a pointer back to the session or
  conversation that produced the lesson, so a future reader can go find the original
  incident if the one-liner isn't enough.

Body convention: a one-line fact first, then for `feedback` and `project` types, a **Why**
line (the incident that earned it) and a **How to apply** line (the concrete behavior
change). A `user` or `reference` fact can be just the one-liner if there's nothing more to
say. Cross-link related memories with `[[other-slug]]` so a reader who lands on one fact
can follow the thread to related ones.

## The four types

- **`user`**: who the person on the other end is, role, standing preferences, how they
  like to work. Stable facts about a person, not a project.
- **`feedback`**: agent behavioral meta-guidance. How the agent should work, generalized
  past the one incident that produced it. This is the type that's actually portable across
  projects, which is why it's the type worth building a starter pack out of.
- **`project`**: ongoing work, goals, or a convention that isn't derivable from reading the
  code. Things true about this specific project right now, not a general behavior rule.
- **`reference`**: a pointer to an external resource, a doc, a spec, a tool's quirks. Not a
  fact in itself, a link to where the fact lives.

## The index (`MEMORY.md`)

`MEMORY.md` is the file that's always loaded, every session, no exceptions. Each line
points at one fact file:

```markdown
[Title](slug.md) - one-line what-it-teaches
```

Keep it flat while it's small, a simple list is easier to scan than a taxonomy nobody
needs yet. Once it grows past a screenful, split it into named sections (by type, by area,
whatever groups actually help). Growing structure only when the flat version starts
failing is the right order, not the reverse.

Prune the index and the fact file together, in the same edit. An index line pointing at a
deleted file, or a file with no index line, both silently stop being read. Neither error
shows up until something goes wrong for a reason nobody can trace.

## The routing discipline

This is the part that matters more than the file format. Before writing anything to
memory, decide where the fact actually belongs. Three destinations, in order of how much
weight they carry:

1. **Nowhere.** Re-derivable facts (anything visible by reading the code), common
   knowledge, and one-off corrections that won't recur don't need a permanent home. Most
   candidate memories fail this test and that's fine. Writing everything down is not the
   same as writing down what's useful.
2. **The project's own instructions file** (its `CLAUDE.md` or equivalent), if it's a
   project fact or convention the whole team should share. This is the single source of
   truth for anything project-wide: conventions, architecture decisions, standing rules.
   Memory is personal and session-scoped in spirit; the project's instructions file is
   shared and versioned. A fact everyone on the project needs belongs there, not in one
   person's memory folder.
3. **Memory**, and only for genuine agent behavioral meta-guidance: how the agent should
   work, generalized past the one incident that taught it. This is the `feedback` type,
   and it's the narrowest of the three destinations on purpose.

The corollary follows directly: if a rule in the project's instructions file keeps getting
violated, the fix is structural, a hook, code that makes the wrong path physically
impossible, or tighter phrasing in the rule itself, not a duplicate copy of the same rule
pasted into memory. Memory and the instructions file carry equal authority to the agent
reading them both. A second copy of a rule doesn't enforce it any harder. It just adds a
second place that can drift out of sync with the first, and now there are two files to
keep straight instead of one file to fix properly.

## Hygiene

Not everything that looks like a memory candidate deserves to live forever.

- **Transient notes are disposable scaffolding.** A session-status note, "here's where the
  work currently stands," a running bug list, these exist to carry context across a short
  gap, not to persist. Once the work lands, delete the file and its index line together.
  Leaving it in place is how an index fills up with facts about work that finished months
  ago.
- **Durable project material belongs in a committed repo doc**, not a personal memory
  file. If something needs to survive and be visible to the whole team, that's a sign it
  should live in the project's own docs, not in one person's `memory/` folder.
- **Bias subtractive.** Every kept line needs a reason it's still worth loading on every
  session. When in doubt, that's a signal to cut, not to keep "just in case."
- **Treat old memories as point-in-time observations, not live state.** A fact written six
  months ago described the world as it was then. Before asserting an old memory as current
  fact, especially about how code behaves, check it against the actual code first. This is
  a staleness contract: memory tells you what was once true and worth remembering, not
  what is guaranteed true right now.
