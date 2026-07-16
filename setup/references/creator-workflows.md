# What credible creators and educators teach about Claude Code workflows

> Verified against primary and official sources where possible; hearsay flagged at the bottom.

## Consensus practices (multiple independent credible sources)

1. **Give the agent a verification loop; evidence over assertion.** The single most-repeated tip. Anthropic's official best-practices doc and the team's power-user tips call verification "the #1 tip" (tests, build exit codes, screenshots, browser access; have Claude show test output rather than claim success). Boris Cherny frames it as "can the agent run the thing?", not just lint/unit tests. Simon Willison: agent-controlled validation is one of two backbone steps of every reliable workflow he publishes. Addy Osmani: existing test suites are the feedback loop agents need. Matt Pocock: AI writes the failing test first (TDD) so it can't cheat.

2. **Explore → plan → implement, with the spec as the leverage point.** Boris Cherny: "pour your effort into the plan so Claude can one-shot the implementation." Osmani calls it "waterfall in 15 minutes" (spec.md before any generation). Pocock's "grill me" skill and the official docs' "let Claude interview you" pattern invert it: have Claude interrogate *you* until shared understanding, then write the spec, then execute in a fresh session. Consensus caveat: skip planning for one-sentence diffs.

3. **Context is the scarce resource; clear it aggressively.** Official docs: performance degrades as context fills; `/clear` between tasks; after two failed corrections, restart with a better prompt. Pocock: LLMs have a ~100k-token "smart zone", prefer clearing over compacting. Philipp Spiess (Tailwind): "agents become more unpredictable the longer a conversation goes." IndyDevDan's "Big Three/Core Four" puts context first. The MCP-bloat literature is the same principle applied to tooling.

4. **Parallel sessions in git worktrees.** Boris runs ~5 parallel checkouts, shipping 20-30 PRs/day. Official tips: 3-5 sessions via `claude --worktree`, named and color-coded. Willison flags the failure mode: "parallel agent psychosis" from tracking too many simultaneous sessions.

5. **Short, ruthlessly pruned CLAUDE.md; turn repeated corrections into durable memory.** Docs: for each line ask "would removing this cause mistakes?"; bloated files get ignored. Boris: when Claude repeats an error, have it write the lesson into CLAUDE.md or a skill rather than fixing just that session. Teams check settings.json/CLAUDE.md into git.

6. **Deterministic hooks beat advisory instructions.** Official docs: hooks for "actions that must happen every time with zero exceptions." Anthropic power users chain Stop hooks that re-run tests and force Claude to continue until green. Willison's "mechanical constraints beat probabilistic behavioral instructions" is widely quoted.

7. **Fresh-context adversarial review; maker/verifier split.** Docs: a subagent reviewing the diff in a clean context isn't biased toward code it just wrote. Boris spawns competing subagents where later ones challenge earlier findings to kill false positives. Osmani spawns a second AI session to critique the first.

8. **Point at reference implementations, don't describe from scratch.** Willison: paste a GitHub URL of a similar project and have Claude clone it to /tmp first. Official docs: "look at HotDogWidget.php... follow the pattern." Cat Wu: query git history for previously built similar features.

## Anthropic-internal usage patterns

- **Boris Cherny** (Head of Claude Code): hasn't hand-written code in ~8 months; 5 parallel terminal tabs, each its own checkout; plan mode → one-shot implementation; 20-30 PRs/day. By mid-2026 he no longer prompts directly, he "writes loops" that decide what to build next; roughly half his engineering happens from his phone via remote control + voice.
- **Hard numbers** (Acquired Unplugged via WorkOS, Jun 2026): >90% of the Claude Code team's code written with Claude Code; Anthropic doubled engineering while merges/engineer/day rose ~200%; new-engineer ramp-up dropped from weeks to ~2 days. Staffing advice: "fewer people than you think, abundant tokens."
- **Cat Wu** (Head of Product): "do the simple thing first"; built a skill where Claude launches the desktop app, clicks through the UI with computer use, finds edge cases, fixes, re-verifies; routes debugging through Slack channels before touching code. Prototypes replaced PRDs internally.
- **Migrations pattern**: Claude builds a to-do list, then parallel subagents burn through items; engineers spend $1,000+/month on tokens for this.
- **Anthropic's usage research** (anthropic.com/research/claude-code-expertise): average user on it 20 h/week; humans make ~70% of planning decisions but only ~20% of execution decisions; domain expertise (not coding skill) predicts success; Oct 2025 → Apr 2026, debugging sessions halved while ops/analysis/docs doubled.
- Favorite internal slash commands: /commit, /feature-dev, /code-review.

## Creator-specific notable workflows

- **Boris Cherny** → loops over prompts: automated workflows that prompt Claude and pick the next task; agent dashboard replacing six terminal tabs.
- **Geoffrey Huntley** → the **Ralph Wiggum loop** (May 2025): a bash while-loop re-feeding the same prompt until a done-condition holds. He warns against unattended use: "you really want to babysit this thing."
- **Matt Pocock** (Apr 2026 workshop) → Ralph-style "night shift": grill-me interview → PRD → kanban of vertical-slice ("tracer bullet") issues → AFK loop with test/typecheck feedback; humans keep QA as the "taste" gate.
- **IndyDevDan** → "Big Three/Core Four" framework (context, model, prompt, tools); AFK agents with closed-loop prompting for error recovery.
- **Simon Willison** → publishes full session transcripts; readme-driven development + red/green TDD; per-task model downgrading; clone-a-reference-repo pattern.
- **Steve Sewell** (builder.io CEO) → abandoned Cursor entirely; Claude-first interface, only "peeks" at code during review; multiple parallel instances. builder.io publishes the widely-shared "50 Claude Code tips".
- **Addy Osmani** (Jan 2026) → "model musical chairs" (switch models when stuck); granular commits as save points; "never commit code you cannot explain."
- **Philipp Spiess** (Tailwind) → amnesia-model prompting (exhaustive context every time); voice dictation (Superwhisper) for long prompts; built-in tools over MCP.
- **Cole Medin** → "stop vibe coding": context engineering + RAG for agent builds.
- Not covered (couldn't verify this pass): Theo / ThePrimeagen positions.

## Contested or outdated advice

- **"Always use plan mode."** Boris moved from plan mode to auto mode by mid-2026 (newer models need less explicit planning); official docs say skip planning when the diff fits in one sentence. "Plan everything" is softening into "plan when uncertain or multi-file."
- **"Add MCP servers for everything."** Strong 2026 pushback: a five-server setup could eat 50k+ tokens (Scott Spence measured ~85% savings from on-demand loading). Current pattern: one MCP per external system, thin skills on top, or plain CLI tools (`gh`, `aws`); official docs call CLIs "the most context-efficient way." Deferred tool loading has partly mooted the original complaint.
- **`--dangerously-skip-permissions` as the default.** Ubiquitous in 2025 posts; official guidance now steers to auto mode, allowlists, and OS-level sandboxing instead.
- **Fully autonomous Ralph loops.** The originator disputes hands-off use ("amplifier of operator skill... babysit this thing"). Consensus: loops for mechanical work (migrations, make-tests-pass), humans for taste and QA.
- **Long CLAUDE.md as a knowledge base.** Now an anti-pattern: bloat makes Claude ignore rules; prune ruthlessly, move situational knowledge into on-demand skills.
- **Relying on auto-compact.** /clear + small tasks over compaction; compaction is fallback, not strategy.
- **Vector-DB / RAG codebase indexing.** The Claude Code team found agentic search (grep/glob driven by the model) outperforms RAG indexing; 2024-era embedding advice is obsolete for this tool.
- **One-shot "vibe coding" for production.** Displaced in 2026 by "agentic engineering" (research → plan → execute → review → ship, human as overseer); vibe coding survives only as a prototyping mode.

## Sources

- https://code.claude.com/docs/en/best-practices · https://support.claude.com/en/articles/14554000-claude-code-power-user-tips
- https://newsletter.pragmaticengineer.com/p/building-claude-code-with-boris-cherny
- https://www.anthropic.com/research/claude-code-expertise · https://www.anthropic.com/news/how-anthropic-teams-use-claude-code
- https://every.to/podcast/how-to-use-claude-code-like-the-people-who-built-it (Oct 2025)
- https://www.theneuron.ai/explainer-articles/claude-code-creators-boris-cherny-and-cat-wu-explain-how-to-use-agent-loops/ (Jun 2026)
- https://workos.com/blog/boris-cherny-claude-code-acquired-interview-takeaways · https://fortune.com/2026/06/11/anthropic-claude-boris-cherny-doesnt-write-code-by-hand-anymore/ · https://www.lennysnewsletter.com/p/head-of-claude-code-what-happens
- https://www.latent.space/p/claude-code (May 2025) · https://vlad.build/cc-pod/
- https://simonwillison.net/tags/claude-code/ · https://github.com/simonw/claude-code-transcripts
- https://addyosmani.com/blog/ai-coding-workflow/ · https://spiess.dev/blog/how-i-use-claude-code
- https://www.builder.io/blog/claude-code · https://www.builder.io/blog/claude-code-tips-best-practices
- https://github.com/shanraisshan/claude-code-best-practice/blob/main/videos/claude-matt-pocock-24-apr-26.md
- https://ghuntley.com/ralph/ · https://www.theregister.com/2026/01/27/ralph_wiggum_claude_loops/
- https://agenticengineer.com/tactical-agentic-coding · https://www.youtube.com/@indydevdan/videos · https://www.youtube.com/@ColeMedin
- https://scottspence.com/posts/optimising-mcp-server-context-usage-in-claude-code

**Confidence flags.** Verified: official docs content, Anthropic research stats, Boris/Cat quotes (multiple independent write-ups agree). Hearsay/unverified: Huntley's "3-month loop built a programming language"; "Claude Code = 4% of public GitHub commits"; "Boris ships 200-300 PRs/month" (search-summary only). Podcast-derived items rely on transcripts/summaries, not audio.
