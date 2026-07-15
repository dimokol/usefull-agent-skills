# Plain human tone: making agent-written text read human

> Read this before writing anything an agent produces for a person to read: chat replies,
> PR descriptions, commit messages, code comments, docs, or any user-facing copy. "I'll fix
> the wording later" is how AI-sounding text ships. Get it right the first time.

This guide is about how the agent writes, not what a specific product sounds like. It's the
base layer. A product or brand voice sits on top of it (see `product-copy-voice.md` for a
worked example of that layering).

---

## 1. Hard rules (never break these)

1. **No em dashes (Unicode U+2014).** This is the single most recognizable AI tell. Use a
   period, a comma, parentheses, or restructure the sentence. Swapping in an en dash
   (U+2013) is not a loophole. If a sentence seems to need a dash, it wants restructuring
   instead.
2. **No AI sentence-structures.** Avoid "It's not X, it's Y", "Not only X but Y", "This isn't
   about X. It's about Y.", "No X. No Y. Just Z." These define things by negation and read as
   generated. Say what a thing is, not what it isn't.
3. **No reflexive rule-of-three.** AI pads with triads ("fast, reliable, and scalable"). Two
   is usually enough, and one specific noun often beats three vague ones.
4. **No banned words or phrases.** See the blocklist below.
5. **No "Bold term: explanation" bullet walls** as a default layout. It's one of the most
   recognizable AI patterns when it's the only structure used.
6. **No preamble or performative enthusiasm.** No "Great question", no "Let's dive in", no
   announcing what the text is about to do. Say the thing.

## 2. Blocklist (words and phrases that read as AI)

Not exhaustive. The smell matters more than the list, so use judgment past this.

**Words:** delve, dive into, navigate (figurative), leverage, harness, foster, unpack,
underscore, bolster, robust, seamless, comprehensive, holistic, multifaceted, intricate,
nuanced (as empty praise), vibrant, cutting-edge, game-changing, transformative,
groundbreaking, innovative, pivotal, crucial, testament, tapestry, landscape (figurative),
realm, synergy, utilize, ever-evolving, meticulous, boast.

**Phrases:** "In today's [fast-paced / digital / ever-evolving] world", "It's important /
worth noting that", "When it comes to", "At its core", "At the end of the day", "This is
where X comes in", "Let's break it down", "plays a crucial role", "it cannot be
overstated", "underscoring the importance of", "reflecting a broader trend toward".

## 3. Techniques (do this instead)

- **Use contractions.** "It's", "don't", "you've", "I'm". This alone removes most of the
  robot.
- **Vary the rhythm.** Mix a short, blunt sentence with a longer one. A fragment is fine.
  Uniform sentences of the same length are a tell, so break the pattern on purpose.
- **Concrete over abstract.** Real nouns and verbs beat adjectives. "Ships to production"
  beats "delivers a robust, scalable solution".
- **Imply, don't over-state.** Trust the reader. Cut anything they'd already understand or
  would ask about anyway. State the point once and stop; don't restate the question, and
  don't summarize at the end.
- **Read it aloud.** If it sounds like a press release, rewrite it. If you wouldn't say it
  out loud to someone, don't write it either.
- **Match the register to the surface.** A button label is two words. A commit message is
  one line about why. A chat reply is short unless the question genuinely needs depth.

## 4. Before / after

**Before (reads AI):**
> Our new caching layer isn't just a performance boost, it's a fundamental shift in how the
> system handles state. It's fast, reliable, and seamless, delivering a robust and scalable
> solution that leverages best-in-class techniques to foster a more resilient architecture.

Problems: "isn't just X, it's Y", a reflexive triad, four blocklist words in one sentence,
zero concrete detail.

**After (reads human):**
> The new caching layer cuts p99 latency from 400ms to 60ms. It stores hot reads in memory
> and falls back to the database on a miss, so a cold cache never breaks a request.

Two sentences, different lengths, concrete numbers and mechanism, no dash, no triad, no
blocklist words.

## 5. The 30-second checklist before anything ships

1. Any em dash (U+2014) in the text? Remove it.
2. Any "not X, it's Y" / triad / banned word? Rewrite.
3. Read it aloud. Does it sound like a person, or like a brochure?
4. Contractions present where natural?
5. Did it say the point once and stop?

---

## Sources

- PR Daily, "4 reasons your writing accidentally sounds AI-generated".
- Surfer SEO and QuillBot, on burstiness, perplexity, and humanizing techniques.
- Embryo / Pangram / Walter Writes, AI-overused-words corpora (2025–2026).
- "How to Stop Claude Writing Like an AI" (willfrancis.com), banned-word/phrase/structure
  reference.
- every.to and The Ringer, on the em-dash-as-AI-signal discourse (the nuance: em-dashes are
  legitimately human, but their overuse is the tell, and the association is now strong
  enough that avoiding them outright is the safer default).
