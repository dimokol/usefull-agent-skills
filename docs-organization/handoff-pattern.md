# Writing a handoff

A handoff is a resume doc: a short file that lets a fresh session, or a
teammate who wasn't in the room, pick up unfinished work cold. It's not a
status update and it's not a task tracker entry. It's the "how to resume"
detail that's too long to fit in a task description, and too specific to
the moment to live anywhere permanent.

## When to write one

Write a handoff when work spans more than one session and the next session
won't have the context this one built up: a multi-step migration paused
partway, a branch blocked on something external, a design decision that
took real back-and-forth to reach. If the work finishes in one sitting, skip
it, there's nothing to hand off.

Don't write one just to log progress. If a task tracker or PR description
already captures "what's deferred," a handoff only earns its place when the
resume steps themselves need explaining.

## What every handoff must carry

A fresh session should need nothing else once it opens the file.

- **Breadcrumb to the originating context.** The session ID (or equivalent)
  that wrote it, plus a human-readable name describing what that session was
  doing, in one line. Never the ID alone, an opaque identifier tells nobody
  anything.
- **Current state.** What's actually done, in concrete terms: commits made,
  files changed, decisions locked in. Not "made progress," but what
  specifically landed.
- **The exact next step.** Not "continue the migration," but the actual next
  action: which file, which function, which command to run first. Whoever
  reads this should be able to start typing within a minute.
- **Open loops.** Anything still undecided, any question waiting on someone
  else's answer, any precondition the next session needs to check before
  proceeding (a dependency merging, a review landing, an external service
  being reachable).
- **Where to find more.** Links or paths to the spec, the plan, the branch
  or worktree, the relevant task tracker entry, so the resuming session can
  go deeper if the summary isn't enough.

Keep it self-contained and in plain language. Someone reading this for the
first time shouldn't have to know internal shorthand, ticket codes, or
context that only made sense in the original conversation.

## Template

```markdown
# <topic> handoff

## Session
Originating session: <session-id>
What that session was doing: <one-line gist of the first prompt/ask>

## Current state
- <what's done, concretely: commits, files, decisions>
- <...>

## Next step
<the exact next action: file, function, or command to start with>

## Open loops
- <undecided question, or precondition to check first>
- <...>

## References
- Spec: <path or link>
- Plan: <path or link>
- Branch/worktree: <name and location>
- Task tracker entry: <link>
```

## After it's picked up

Once a session starts the work, it should mark the handoff as taken (moving
it to a "handed" location, flipping a status field, whatever the project's
convention is, see `docs-structure.md` for one such convention) so nobody
else starts the same work twice. Update the handoff if the state changes
significantly enough that the next reader would otherwise be misled.
