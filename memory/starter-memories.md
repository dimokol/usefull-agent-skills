# Starter memories: a pack worth seeding

Thirteen generic behavioral memories, each one earned by a real incident on a real project,
generalized here past the origin so they apply anywhere. Copy the ones that fit your own
work, drop each one in your `memory/` folder as its own file, using the frontmatter and body
shape from [memory-system](memory-system.md). Skip the ones that don't apply. A memory
folder full of rules nobody ever violates is just noise.

---

## 1. Subagent git-WIP safety

**Fact:** a dispatched subagent must never run state-changing git commands (stash, reset,
checkout, commit, rebase). The working tree may hold uncommitted work the subagent can't
see.

**Why:** a subagent operating on the same working tree as a human's in-progress edits can
silently destroy work it has no way of knowing exists. There's no undo for a stash that
gets popped over, or a reset that discards uncommitted changes.

**How to apply:** give subagents read-only git access. After any subagent has touched the
tree, check `git status` and `git stash list` before trusting the state.

## 2. Iteration is a different mode than implementation

**Fact:** the first "this looks off" flips the work from build-mode into verify-each-change
mode, and it stays there until the human says the result is ready.

**Why:** during polish, plowing ahead on the next guess compounds a wrong one. Two or three
uncorrected wrong guesses in a row cost more time than checking after each one would have.

**How to apply:** on the first correction, slow down. Verify each subsequent change against
the actual target before moving to the next one, instead of batching several guesses and
checking at the end.

## 3. Do not commit during iteration

**Fact:** while iterating toward a target, let changes accumulate uncommitted and commit
once, only on the human's explicit go. If a prior pass left stray per-task commits, soft-reset
them into one.

**Why:** mid-iteration commits litter the history with half-finished states nobody will ever
want to check out or read back later.

**How to apply:** hold off on committing until the human says the result is ready, then make
one clean commit.

## 4. Do not push until the human has seen the diff

**Fact:** local commits are fine to make freely. `git push` waits for explicit approval.

**Why:** a push is an outward action. It's visible to other people and other tools the
moment it happens, and it's much harder to walk back cleanly than a local commit.

**How to apply:** stop at "ready to push" and ask, rather than pushing as the last step of a
task by default.

## 5. Deduplicate before adding

**Fact:** when the same logic already sits in two or more files, recommend extracting it as
part of the current task, not as a follow-up.

**Why:** duplication compounds, and "later" rarely arrives. The next change to that logic
either updates one copy and misses the other, or updates both and doubles the diff.

**How to apply:** call out the duplication when it's found, and do the extraction in the
same change rather than filing it away.

## 6. Best solution first, and fix bad foundations

**Fact:** lead with the strong version of a solution. Push back on a suboptimal ask before
implementing it. Never silently build new work on top of a foundation that's already known
to be wrong, fix it or flag it instead.

**Why:** an agent's default is to take the literal ask at face value and build on whatever
is already there, even when both are worse than the available alternative.

**How to apply:** propose the clean path as the default, not as an optional aside, and
surface any foundation problem the task touches instead of quietly working around it.

## 7. Spec before code

**Fact:** for any non-trivial piece of work, pin down what, where, the expected behavior,
and the constraints, before writing implementation. Ask when any of those is vague.

**Why:** an unexamined assumption made in the first five minutes is the single most common
source of wasted work on a task.

**How to apply:** write or request a short spec as a gate before starting implementation,
even a one-paragraph one.

## 8. One feature per session

**Fact:** keep one workstream per session. Don't interleave multiple features, and don't run
parallel sessions against the same project at the same time.

**Why:** a cluttered context makes an agent slower and more error-prone, and parallel edits
against the same project risk stepping on each other.

**How to apply:** when a new, unrelated ask comes in mid-task, queue it for a fresh session
instead of folding it into the current one.

## 9. Never stop short

**Fact:** finish every step of a task. If something is genuinely unfinished, list the
unfinished items and any open questions at the end of the message, never buried in the
middle.

**Why:** a question asked mid-stream gets missed, and work that's actually half-done but
reads as complete leads to a false sense that nothing is left.

**How to apply:** end-load anything that still needs a decision or a follow-up, clearly
marked, instead of scattering it through the response.

## 10. Merge-conflict resolution preserves both sides

**Fact:** when resolving a merge conflict, both sides keep their full functionality. Never
resolve by taking one side wholesale (no blanket "keep theirs" or "keep ours" as a
shortcut). If the two sides are genuinely irreconcilable, stop and flag it instead of
guessing.

**Why:** picking one side silently drops working behavior that the other side depended on,
often without any error to signal that it happened.

**How to apply:** integrate both sides' intent into the merged result. Escalate to a human
when that's not actually possible rather than picking a winner.

## 11. Verify against the real output, not a proxy

**Fact:** a metric, a probe value, a measured width, or a font check does not by itself
prove a visual or behavioral match. Check the actual rendered result or the actual observed
behavior. When something "never seems to fire," instrument it before tuning it further.

**Why:** a proxy signal can pass every check while the real output is still visibly wrong,
because the proxy and the target aren't actually the same thing.

**How to apply:** look at the thing itself, the rendered screen, the real request, the
actual log line, before declaring a change correct.

## 12. Images the agent opened are not visible to the human

**Fact:** a screenshot or image file the agent read is not automatically visible to the
human on the other end. To let them actually judge it, hand over something they can open: a
served URL or a file path.

**Why:** an agent that opened and looked at an image tends to assume a shared view exists
between it and the human, when in most setups it doesn't.

**How to apply:** for anything visual, always surface a link or a path the human can open
themselves, don't just describe what was seen.

## 13. Label evidence by source before anchoring

**Fact:** when working from a pasted chat log, thread, or transcript, identify each line's
role and author before treating it as ground truth. Check sibling code paths before
committing to a single root cause.

**Why:** a confident-sounding line from the wrong source, a guess stated as fact, a comment
from someone without full context, can mislead just as easily as a line from an authoritative
source.

**How to apply:** attribute each piece of evidence to who said it and how much they'd
actually know, corroborate it against the code or other sources, and only then settle on a
conclusion.
