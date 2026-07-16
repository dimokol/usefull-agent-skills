# Design: machine-pressure coordination

Why this exists and what it deliberately does not try to do. If you just want to install the
badge and hook, see `README.md` in this directory; this file is the reasoning behind the choices.

## The problem

Running several AI agent sessions in parallel, each in its own terminal tab, on a single laptop
can cause severe, repeated lag. The pattern is easy to reproduce: five or more sessions open at
once, several of them spawning their own MCP subprocesses (browser automation, dev servers,
installs), free RAM dropping toward zero, and the whole machine grinding to a crawl, even though
CPU usage looks moderate. Nothing in the default setup gives a session any visibility into what
the other sessions are doing to shared resources; each tab acts blind to the rest.

## The root cause: RAM, not CPU

On a typical 16 GB laptop, memory is the binding constraint. You hit swap-thrash lag long before
CPU or thermal limits become the bottleneck. Once the OS starts pushing memory out to disk and
swap fills, every memory access can hit disk, and the whole machine feels sluggish, even when the
CPU looks idle. That's why the pressure probe treats **swap %** as the signal that most directly
explains "why does everything feel slow right now," not CPU.

Corollary: a monitor that only tracks CPU would miss the actual failure mode. The probe tracks
five signals (CPU, RAM, swap, load, disk) and reports the worst of them, because any one of them
maxing out is enough to explain a stall.

## Goals and non-goals

**Goals:**

1. **Visibility.** Live pressure (memory/swap/load/disk) in every tab, so a stall has an obvious
   explanation instead of feeling random.
2. **Advisory plus last-resort safety.** Warn before an agent-initiated heavy op under elevated
   pressure; hard-stop only at genuine RED, to prevent thrash into an unresponsive machine.
3. **Cut the structural multiplier.** The badge helps you notice pressure, but the real fix for
   recurring thrash is reducing what spawns automatically per session (heavy MCP servers, orphaned
   automation browsers) rather than only reacting to it after the fact.

**Non-goals (deferred):**

- A true cross-session semaphore/queue that serializes heavy ops beyond a simple "1 at a time" cap
  for the highest-value classes (e2e, docker).
- Coordinating commands a human types directly in a terminal. Hooks only see an agent's own tool
  calls; anything typed by hand is invisible to this system.
- A GUI or menubar app. A statusline badge plus an on-demand CLI snapshot is enough.

## Why a shared probe, not one check per consumer

`pressure.sh` is the single source of truth for thresholds and levels. The statusline widgets, the
PreToolUse hook, and any ad-hoc self-check all call the same script. That means tuning a threshold
happens in exactly one place, and it means the hook's RED/AMBER classification can never drift out
of sync with what the badge is showing you. The 4-second on-disk cache exists so that six
statusline widgets rendering in the same tick sample the machine once, not six times, and so N
open tabs sample the machine at most once every 4 seconds combined, not N times.

The probe reads only cheap, built-in signals (`vm_stat`, `sysctl vm.swapusage`, `sysctl
vm.loadavg`, `df`), deliberately avoiding anything that needs a sampling wait (true instantaneous
CP %) or elevated privileges (`sudo powermetrics` for real temperatures). A statusline widget that
takes longer than the render budget is worse than no widget.

## Key constraint: agents can run in a permission-bypass mode

Agent CLIs commonly support a mode that skips interactive per-command approval prompts. That mode
removes the option of an "are you sure?" dialog as an enforcement mechanism: a hook that tries to
`ask` for confirmation just auto-allows, because there's no one there to answer the dialog. The
only enforcement levers that still work under bypass mode are a hard `deny` from the hook, or a
non-zero exit code.

This is why the design has exactly two enforcement tiers, and why they map the way they do:

- **AMBER** injects `additionalContext`, text the agent sees and is expected to relay or weigh
  before proceeding. This only works because the agent is cooperating; it is not a hard block.
- **RED** returns `permissionDecision: deny`. This is the one thing that survives bypass mode, so
  it's reserved for the case that actually risks a frozen machine (imminent swap-thrash), not used
  for routine caution.

## Fail-open, always

Every failure path in the probe and the hook defaults to allowing the operation. No `jq` on the
machine: allow. The probe script errors or returns garbage: allow. The pressure JSON fails to
parse: treat it as `OK` and allow. A monitoring system that can itself block real work when it
breaks is worse than no monitoring system, because now a tooling bug costs you productivity on top
of whatever it was supposed to prevent. The only thing that blocks is a confirmed, parseable RED
reading, or a live, confirmed concurrent heavy op of the same class.

## Escape hatch

Even the RED block is meant to be a speed bump, not a wall: a human who has judged that the
reading is wrong, or that proceeding is fine anyway, can prefix the exact command with
`PRESSURE_OVERRIDE=1` and it goes through immediately. The design deliberately makes this an
explicit, visible act (part of the command text itself) rather than a persistent toggle, so an
override is a one-time decision, not a standing setting an agent could quietly leave on.

## Deferred: a real queue

The current concurrency cap for e2e and docker is a `pgrep`-based "count what's actually running"
check, capped at 1, with no lock files. That sidesteps an entire class of stale-lock bugs (a
crashed process just stops showing up in `pgrep`, so there's nothing to clean up), at the cost of
being deny-and-retry rather than wait-and-proceed. A true queue, where a second session blocks
until a slot frees rather than being told to try again later, is a reasonable Phase 2 if
deny-and-retry turns out to be annoying in practice. It needs careful handling of slot release on
crash, which is exactly the complexity the current design avoids by not persisting any state at
all.
