# Claude Code best practices

> Output of an adversarially verified research pass (104 independent agents; every claim survived a 3-voter refutation panel, most verified verbatim against live primary sources). Meta-finding worth knowing: **only Anthropic primary sources survived verification.** Community claims (Reddit, HN, YouTube, "best MCP" lists) all failed the evidence bar; the community picture lives in the companion ecosystem list (`recommended-ecosystem.md`) and `creator-workflows.md` in this repo, with looser sourcing, flagged as such.

## The verified playbook

**CLAUDE.md size and content**
- Keep every CLAUDE.md ruthlessly concise: for each line ask whether removing it would cause mistakes; official target **under 200 lines per file**; bloated files reduce adherence ("Claude ignores rules lost in the noise"). Docs state the adherence claim without published measurements.
- **@path imports do not reduce context**: imported files load in full at launch. Splitting helps organization only. To actually save context, move detail to docs/skills that are read on demand.
- Treat CLAUDE.md like code: commit the project file to the repo root, update with documentation-level rigor, iterate on it like a prompt. Only broadly applicable content belongs there (it loads every session).

**Instruction hierarchy** (four levels, loaded broadest to most specific, concatenated, not overriding)
1. Managed policy (`/Library/Application Support/ClaudeCode/CLAUDE.md` on macOS)
2. User `~/.claude/CLAUDE.md` (all sessions)
3. Project `./CLAUDE.md` or `./.claude/CLAUDE.md` (checked in)
4. Gitignored `./CLAUDE.local.md` (personal per-project notes)

Plus: parent-directory files load automatically (monorepos), child-directory files on demand, imports max 4 hops, and **`.claude/rules/*.md` with YAML `paths` frontmatter** for larger projects, so rules only enter context when Claude touches matching files. Project rules load after (and outrank) user rules. Caveats: path-scoped rules trigger on file reads, not writes; a reported bug (#21858) has `paths` ignored in user-level `~/.claude/rules/`; gitignored files don't propagate to worktrees (use a home-dir @import if needed).

**Mechanism choice by enforcement level** (the single most decision-useful finding)
- **Hooks** for rules that must always hold: deterministic, guaranteed. (Third-party corroboration a verifier found: ~70% adherence for a CLAUDE.md rule vs 100% via hook; single-blog quality.)
- **CLAUDE.md** for broad advisory rules.
- **Skills** for sometimes-relevant domain knowledge, loaded on demand.
- Caveat: a blocking Stop hook is overridden after 8 consecutive blocks by default (raisable via `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`).

**Core workflow**
- Explore → plan → implement → commit, with plan mode for the first two phases. Right-sizing rule, verbatim: "If you could describe the diff in one sentence, skip the plan."
- Context is the single most important resource: `/clear` between unrelated tasks; after two failed corrections, `/clear` and rewrite the prompt instead of continuing; push wide investigation into subagents (isolated context windows, return summaries, enable parallelism).
- Verification-centered work: gather context → act → verify → repeat. Prescribed TDD shape: write test specifications first, implement one test at a time, validate at each checkpoint, then expand scope.
- Parallel sessions in git worktrees so edits don't collide; Writer/Reviewer split across two sessions ("a fresh context improves code review since Claude won't be biased toward code it just wrote").

**Automation**
- Official pattern: non-interactive `claude -p` in CI/cron/scripts with `--allowedTools` scoping, or `--permission-mode auto` (classifier blocks risky actions; in `-p` runs it aborts rather than deferring to a user; classifier has open bug reports #49837, #51689).
- Custom slash commands tailored to your codebase are officially recommended (/migrate-db, /add-feature, /security-review before committing).

**Long-running agents** (from the Nov 2025 engineering post; one internal experiment, no published reproducible metrics)
- Most complex projects exceed one context window; the harness matters more than raw model capability. Recommended: an initializer session that creates `init.sh`, a progress file, and an initial commit; subsequent sessions scoped to **one feature at a time**; git as memory (descriptive commits + progress-file summaries; each session starts by reading git log and the progress file).

**Auto memory** (v2.1.59+, on by default)
- Per-project dir at `~/.claude/projects/<project>/memory/`; only the **first 200 lines or 25 KB of MEMORY.md** loads at session start; topic files read on demand; all worktrees of one repo share the dir; not shared across machines.

## Caveats (from the verification pass)

1. Source monoculture: everything above is Anthropic describing its own product; independent community consensus didn't survive verification and lives in the sibling reference files instead.
2. Living docs, verified live; thresholds (200-line target, 8-block cap, 25 KB memory load) are Claude Code 2.1.x-era specifics and can change.
3. The "reduce adherence" claim has no published measurements; treat the 200-line figure as a heuristic.
4. The scaling PDF is enterprise-oriented; commit-to-main and PR-rigor advice needs adaptation for a solo dev.

## Open questions the pass could not settle

- Which MCP servers, plugins, and skill packs are worth installing vs. hype (no community claim survived verification; `recommended-ecosystem.md` covers it with adoption signals and keep/skip reasoning instead).
- Verified best practice for multi-account/profile setups (nothing official exists yet; a personal multi-account `CLAUDE_CONFIG_DIR` split, one config directory per account, is already ahead of the documentation).
- Stability of scheduled/cloud routines and recurring self-audit patterns beyond `claude -p`.
- Empirical backing for the 200-line target.

## Primary sources

- https://code.claude.com/docs/en/best-practices (anthropic.com/engineering/claude-code-best-practices redirects here)
- https://code.claude.com/docs/en/memory
- https://code.claude.com/docs/en/hooks-guide
- https://www.anthropic.com/engineering/building-agents-with-the-claude-agent-sdk
- https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents · https://github.com/anthropics/cwc-long-running-agents
- https://resources.anthropic.com/hubfs/Scaling%20agentic%20coding%20across%20your%20organization.pdf (verified page-level)
- https://www.anthropic.com/news/automate-security-reviews-with-claude-code
