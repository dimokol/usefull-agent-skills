# Editing guide index: "I want to change X, edit here"

A single table that maps every editable concern in a project to the one
file or token that owns it. The point is that nobody, human or agent, ever
has to hunt through the codebase to find where a given thing lives. If a
value is duplicated in three places, this pattern doesn't apply until you've
consolidated it down to one source, then the table just names that source.

## Why this exists

Most projects grow a handful of values that get changed often: a color, a
font size, a piece of copy, a spacing rule. Without a single-source-of-truth
discipline, each of these tends to drift into being set in multiple places,
a component's inline style, a config default, a CSS variable, and each one
just slightly out of sync with the others. The next person to change it
either edits the wrong copy, or edits all of them and still misses one.

The fix is boring on purpose: pick the one file or token that owns each
concern, document it in a table, and route every future edit through that
table. When a shared source changes, everything that reads from it follows
automatically.

## The pattern

1. **Find the shared sources.** For any value that shows up in more than one
   place (a color, a size, a piece of repeated copy, a limit), pick or
   create the single file/token that will own it going forward.
2. **Build the table.** One row per editable concern. The left column is
   phrased as an intent ("I want to change X"), not as an implementation
   detail, so someone who doesn't know the codebase can still find their
   row.
3. **Route all edits through it.** When someone (or some agent) asks "where
   do I change the button color," the answer is "check the editing guide,"
   not "grep the codebase and hope."
4. **Grow it as you go.** When you introduce a new shared source, add its
   row in the same commit. An editing guide that falls out of date is worse
   than none, it actively misdirects.

## Illustrative example

A generic three-row example, the shape scales the same whether the table
ends up with three rows or thirty:

| I want to change… | Edit | Notes |
|---|---|---|
| The primary color anywhere in the UI | the `--color-primary` token in the design-tokens file | Never hardcode a hex value; every component reads this token. |
| Body font size across the whole site | the `--font-size-body` token in the design-tokens file | One token drives every paragraph, list, and body-copy element. |
| A section's copy (headline, body text) | that section's data file (e.g. `data/<section>.ts`), not the component | Keeps content edits out of component code, so a copy change never risks a layout change. |

## Keep it honest

The table is only useful while it's accurate. Two habits keep it that way:

- **New shared source → new row, same commit.** Don't let the guide lag the
  code it's supposed to describe.
- **Row disagrees with the code → fix the row or fix the code**, whichever
  is actually the intended single source. Never leave the contradiction for
  the next reader to discover the hard way.
