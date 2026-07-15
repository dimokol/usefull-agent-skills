# Product copy voice: an example of deriving a voice from the base rules

`plain-human-tone.md` is the base layer: it makes any agent-written text read human. A
product still needs its own voice on top of that, tuned to who reads the copy and what they
need from it. This file walks through one worked example of that derivation, for a
service-style product used by a broad, non-technical audience, so you can see the method and
adapt it to your own product.

The method is: start from the base rules, then answer three questions before writing a
single string.

1. **Who reads this copy, and what do they already know?** A checkout flow used by anyone
   off the street reads differently from a developer dashboard. Name the audience honestly,
   including the least technical reader you expect, not the median one.
2. **What does the copy need to do at each moment?** Confirm an action, explain a
   consequence, recover from an error, label a control. Each of those has a different job,
   so they shouldn't all sound the same.
3. **What's the one failure mode to design against?** For this example, it's a user who
   doesn't understand what they just clicked, or feels talked down to. Pick your own failure
   mode; it shapes every rule below.

## The derived voice, for this example

- **Clear and laconic first.** Short sentences, plain words, one idea per line. If a message
  needs a paragraph, the flow probably needs a rethink, not more copy.
- **Professional and friendly.** Warm, never stiff or salesy, never cutesy. Write like a
  helpful person at a front desk, not a mascot.
- **Human, not robotic.** Say things the way a person would say them out loud to the reader,
  not the way a system would log them.

## Always explain, never condescend

- Say what an action does and what happens next, especially before anything irreversible
  (cancel, pay, confirm, delete). No surprises after the click.
- Explain once, clearly. No double explanations, no subtext that repeats the heading, no "as
  you may know".
- Don't assume technical knowledge. Some readers are elderly or non-technical by default,
  not as an edge case. No jargon or internal terms (payload, token, raw field names); name
  things the way the reader would ("your booking", "your email"), not the way the schema
  does.
- On errors, say what happened and what to do next, in plain words. Never show a raw error
  code as the whole message, and never blame the reader for the failure.

## Plain language for everyone

- Prefer the common word over the clever one. Spell out what a control does ("Confirm
  booking", not a bare "Submit").
- If the product ships in more than one language, give every language the same care, and
  check the longer one still fits space-constrained UI (buttons, chips, mobile).
- Write dates, times, prices, and durations in a full, unambiguous form the least technical
  reader can parse at a glance.

## Avoid

- Jargon, internal field names, or dev terms in any string the reader sees.
- Walls of text. If a message needs a paragraph, it probably needs a rethink.
- Scolding errors ("You entered an invalid value"). State the fix instead.

## A different product would derive differently

This example lands on one consistent, plain register throughout, because the audience and
failure mode call for it. A different product answering the same three questions could land
somewhere else. One example: a product with an in-world narrative voice (a game, a
character-driven assistant) might deliberately run two registers, an in-character voice for
flavor text and a plain, unambiguous voice for anything transactional (payments, permissions,
data). That's not a violation of the base rules, it's the same method applied to a different
audience and a different failure mode. The point isn't to copy this example's answer; it's
to run the same three questions against your own product and write down what falls out.
