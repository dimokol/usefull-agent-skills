---
name: setup-audit
description: Use when asked to audit or refresh an agent/CLI setup, check for workflow/config drift, or catch up on ecosystem changes for the tool you use (e.g. Claude Code). Args - "weekly" (light pass, default when no arg given) or "deep" (full periodic re-audit).
---

# Setup audit

Recurring self-audit of your agent/CLI setup: config, memory, skills, hooks, and the ecosystem around them. Two modes; `weekly` is the default when no argument is given.

**Hard rules for both modes:**
- Propose, never apply. Write only inside your designated audit folder (call it `$AUDIT`). Never edit settings files, project instruction files, hooks, or memory as part of an audit run; changes need your explicit go afterwards.
- Deltas only. If nothing changed since the last run, say so in one line; don't re-narrate the known state.
- Confidence labels: anything not verified against a primary source or the actual file on disk is marked unverified.

## Weekly (light) pass

1. **Last run**: read `$AUDIT/automation/weekly-log.md` (create if missing; on first run, baseline against the most recent deep audit and say so). Note the last run's date and its recorded changelog version anchor. Read the audit's top-level recommendations file to know what's still open.
2. **Tool changelog**: fetch the changelog for the CLI/agent tool you're auditing (e.g. for Claude Code, the raw `CHANGELOG.md` from its GitHub repo). It typically has version numbers but no dates, so diff against the version anchor recorded in the previous log section (first run: anchor = your currently installed version). Record the new top version in this run's log section. Flag anything touching: hooks, skills, memory, settings schema, scheduled tasks, notifications, multi-profile/auth.
3. **Ecosystem diff**: fetch a canonical community list for the tool (e.g. `awesome-claude-code`'s README, raw not rendered, since the rendered GitHub page can truncate). Compare its sections of interest (skills, memory/context persistence, linting, usage/cost monitoring, observability, remote control/notifications) against a saved snapshot at `$AUDIT/automation/awesome-snapshot.md` (create as baseline if missing); note additions/removals, then overwrite the snapshot with the new state. Category names drift over time; if one goes missing, track its nearest successor and note the rename in the snapshot.
4. **Local drift tripwires** (read-only: Read/Grep/ls, no edits):
   - **Version-claim vs actual**: for each project whose CLAUDE.md (or equivalent instruction file) states a version/fact that's also recorded elsewhere (e.g. `package.json`), diff the two.
   - **Memory index vs disk**: for each project with a memory index file, diff its listed entries against the actual files present in its memory directory, which catches stale references and un-indexed orphans.
   - **Instruction-file char cap**: any project instruction file with a documented size ceiling. Check its byte count and warn above the cap (e.g. `wc -c <file>`, warn near/above the documented limit).
   - **Dead settings backups**: list your config directories for stray `.bak`/`.backup`/`.orig` files beyond whatever single backup you intentionally keep.
   - **Expired scheduled jobs**: `crontab -l` (and any scoped LaunchAgent/systemd-timer equivalents you maintain) for entries past a "remove after" date noted in their own comment. Empty/no matches = pass.
   - **Guard-hook parity**: if you run the tool under multiple profiles/accounts, diff the full hook arrays between profiles' settings files. They should match unless intentionally different.
   - **Token hygiene**: grep your working directories and downloads for leaked API-key-shaped strings (e.g. `sk-...` patterns); must return nothing.
5. **Log**: append a `### YYYY-MM-DD` section to `$AUDIT/automation/weekly-log.md`: deltas found, a 1-3 line "worth adopting?" verdict on ecosystem news, tripwires that fired. If zero deltas and zero tripwires, append one "no deltas" line.
6. **Report** the section content back in the final message, worth-adopting verdict first.

## Deep (monthly / on-demand) pass

Everything in weekly, plus regenerate the audit itself.

1. **Study agents** (parallel, read-only): dispatch one agent per project/area you actively maintain, one for the global tool setup (config dirs, shared hooks/skills, scheduled jobs), and one sweep agent for everything else you maintain but touch less often. Reuse the prompts' section structure from the existing `$AUDIT/findings/*.md` files so diffs stay comparable across runs.
2. **Research fan-out**: run a deep-research pass (a dedicated research skill if you have one, or a manual fan-out) on current best practices for the tool, plus one agent on the GitHub/community ecosystem and one on creator/tutorial consensus. Refresh `$AUDIT/research/*.md`.
3. **Reconcile, don't overwrite**: update `$AUDIT/findings/` and `$AUDIT/projects/` files; mark previously recommended items as RESOLVED (with date) instead of deleting them, add new findings, re-rank the priority list in the top-level recommendations file.
4. **Report**: top-5 changes since the last deep pass, newly recommended actions, resolved count.

Deep pass is heavy (multi-agent plus web research); confirm before running it inside an unrelated session.

## Methodology note

The deep pass leans on fan-out, not a single long read-through: dispatch N parallel read-only study agents (one per project/area, so each stays focused and none blocks on another), pair that with a deep-research fan-out that searches multiple sources and cross-checks claims against each other adversarially before trusting them (a single blog post asserting "everyone uses X now" is not evidence), then synthesize all of it yourself into one prioritized recommendation list. The fan-out is what makes a monthly deep pass tractable: a single agent reading everything serially either times out or skims. The constraint that makes it safe to run unsupervised is the same as the light pass: every agent in the fan-out is read-only, and the only thing that gets modified is the audit's own output.

## Scheduling (optional)

Running this manually works, but a scoped scheduled job removes the "did I remember to run it" failure mode. If you want to automate the weekly pass, a periodic job runner (a LaunchAgent on macOS, cron, systemd timer, or your tool's own scheduled-agent feature if it has one) can invoke the weekly pass on an interval, writing only inside `$AUDIT` and logging its own output. Scope the job's write permissions to the audit folder only, so even a bad run can't touch your real config. This is optional; the skill works the same run manually or on a schedule.

## Common mistakes

- Running deep when asked for the default: no arg = weekly.
- Editing config during the audit "while at it": never; the audit only writes under `$AUDIT`.
- Overwriting recommendation files in deep mode: reconcile and mark RESOLVED, history is the point.
- Trusting blog claims about installs/adoption without checking: verify stars/recency via the source's own API, or mark unverified.
