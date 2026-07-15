# 📊 Statusline monitor

A live machine-pressure badge shown in your agent's statusline, plus a heavy-op gate, so you can
tell at a glance whether it's safe to kick off heavy work (installs, e2e, builds) when you're
running several agent sessions on one laptop.

Built after repeated memory-thrash lag incidents from running many agents at once. Design
rationale (why swap, not CPU, is the thing that actually causes the lag): see `DESIGN.md` in
this directory.

> **macOS today.** The probe reads `vm_stat`, `sysctl vm.swapusage`, `sysctl vm.loadavg`, and
> `df -g`, all macOS built-ins, chosen because they're cheap enough to run every statusline
> render. Cross-platform (Windows/Linux) probes are a TODO; contributions welcome. See the
> ccstatusline upstream project for cross-platform status-line rendering in general.

| Item | What it solves | Portability |
|---|---|---|
| [pressure.sh](pressure.sh) | Live CPU/RAM/swap/load/disk badge, colored by severity, so you know at a glance whether it's safe to start something heavy. | 🟡 (macOS today) |
| [pretooluse-pressure](pretooluse-pressure/) | PreToolUse hook that blocks heavy ops (install/e2e/docker/build/jest) at RED pressure, warns at AMBER, and caps e2e/docker concurrency at 1 across sessions. | 🟡 (macOS today) |

Here 🟡 means two things at once: the probe itself is macOS-only for now, and both pieces expose
env vars for the parts that are meant to be adapted per machine (see Configuration below).

---

## What you see

```
Opus 4.7 | xhigh | 299.7k | 39.4M | 26.0% | 3hr 13m | 68.0% | 2d 1hr 23m   ← your existing ccstatusline
CPU 52% | RAM 85% | swap 94%▲ | load 13.8 | disk 9G | heavy ops blocked   ← pressure monitor
```

Each segment is an independent ccstatusline widget with native ` | ` separators, colored by
**its own** level so you can see which signal is hot:

🟢 green = OK · 🟡 yellow = AMBER (caution) · 🔴 red = RED (danger)

---

## The segments

| Segment | What it measures | Source | 🟢 OK | 🟡 AMBER | 🔴 RED |
|---|---|---|---|---|---|
| **CPU %** | Recent CPU utilization, normalized to your core count | `ps -A -o %cpu` summed ÷ cores | <85% | 85-97% | ≥97% |
| **RAM %** | Physical memory in use (100 minus available) | `vm_stat` | <85% | 85-93% | ≥93% |
| **swap %** | How full the swap file is (RAM spilled to disk) | `sysctl vm.swapusage` | <70% | 70-90% | ≥90% |
| **load** | 1-min load average (processes competing to run) | `sysctl vm.loadavg` | <12 | 12-24 | ≥24 |
| **disk** | Free space on `/`, in GB | `df -g /` | >20 GB | 10-20 GB | <10 GB |
| **verdict** | Overall, the worst of the five above | - | ✅ clear | ⚠ caution | ⛔ heavy ops blocked |

The load thresholds assume an 8-core machine (1.5x / 3x core count). Scale them for your own
core count in the thresholds block at the top of `pressure.sh`.

### What each one really tells you

- **CPU %** is how hard the processor is working right now, but it's a recent decaying ~1-minute
  average across all processes, not an instantaneous snapshot (a true point-in-time reading needs
  a ~1s sampling wait, too slow to run every render). It lags a sudden spike by a few seconds; for
  "is something hammering the CPU this instant" cross-check with `load`. Capped at 100%.
- **RAM %** is your headroom for starting new work. macOS keeps "available" high by reclaiming
  cache, so this climbing into the 90s means genuine memory pressure.
- **swap %** is the signal that actually causes the lag. Once macOS starts pushing memory out to
  disk and swap fills, every memory access can hit disk and the whole machine feels sluggish, even
  when the CPU looks idle. The **▲** marker appears whenever swap is elevated (≥AMBER): a quick
  "we're spilling to disk" flag. This is the root cause behind most multi-agent lag incidents.
- **load** is queue depth: roughly how many tasks are waiting for a core. A load near your core
  count means "fully busy but keeping up"; higher means work is backing up. It includes I/O wait,
  so it complements CPU % (load can be high from disk thrash while CPU % looks moderate).
- **disk** matters more than you'd expect here: the swap file grows on disk, so memory pressure
  eats disk too, and things like e2e Docker builds need several GB of headroom or they fail with
  ENOSPC.
- **verdict** is your one-glance "is it safe to run something heavy now" answer, set to the worst
  of the five. ⛔ RED is the level at which the PreToolUse hook refuses to launch a heavy op until
  you free resources.

### CPU vs. load, why both

They overlap but aren't the same. **CPU %** is how much processor time is being used. **load** is
how many processes are waiting to run, including those blocked on disk I/O. During swap thrash you
can see moderate CPU but high load (everything's waiting on disk). During a CPU-bound build you'll
see both high. Keep both; they disambiguate each other.

---

## Wiring it up as ccstatusline widgets

1. Install `pressure.sh` somewhere stable (see Install below).
2. Run `npx ccstatusline@latest` and add a new line, or edit an existing one.
3. Add one **Custom Command** widget per segment you want, pointing at:

   ```
   /path/to/pressure.sh --field cpu
   /path/to/pressure.sh --field ram
   /path/to/pressure.sh --field swap
   /path/to/pressure.sh --field load
   /path/to/pressure.sh --field disk
   /path/to/pressure.sh --field verdict
   ```

4. For each widget: `(e)dit cmd`, `(w)idth`, `(t)imeout`, `(p)reserve colors`. **Keep "preserve
   colors" ON**, that's what lets the level-coloring through.
5. Reorder or drop segments freely, e.g. drop `load` if `CPU` feels like enough, or move `verdict`
   first. Same separator picker as your other lines.

A 4s on-disk cache means all six widgets in one render take one real sample (the first widget
computes in ~40ms, the rest read the cache in ~10ms each). The cache is shared across every tab, so
the machine samples at most once every 4s no matter how many sessions you have open.

Any session can also self-check before starting something heavy:

```bash
/path/to/pressure.sh --json
```

### Probe modes

```bash
pressure.sh                 # human one-liner
pressure.sh --json          # machine-readable (hook + ad-hoc self-check)
pressure.sh --statusline    # full single-line badge
pressure.sh --field cpu     # one colored segment: cpu|ram|swap|load|disk|verdict
```

### Tuning thresholds

All thresholds live in one block at the top of `pressure.sh`:

```sh
CPU_AMBER=85;   CPU_RED=97
RAM_AMBER=85;   RAM_RED=93
SWAP_AMBER=70;  SWAP_RED=90
LOAD_AMBER=12;  LOAD_RED=24      # 8-core machine: 1.5x / 3x, scale for your core count
DISK_AMBER=20;  DISK_RED=10
```

Change them there and every consumer (statusline, the hook, `--json`) updates at once.

---

## The pretooluse-pressure hook (the part that actually organizes work)

[`pretooluse-pressure/hook.sh`](pretooluse-pressure/hook.sh), wired in `settings.json` under
`hooks.PreToolUse` (matcher `Bash`). It fires before every Bash tool call and acts only on heavy
ops (`npm install`/`ci`, `test:e2e`/`playwright test`/`e2e.sh`, `docker compose`/`build`/`buildx`,
`npm run build`/`next build`, `jest`). Everything else passes instantly.

| Condition | Action |
|---|---|
| Not a heavy op | allow (silent) |
| **e2e already running** in any session | **DENY**, they tend to collide on host ports and thrash the machine (concurrency = 1) |
| **docker build/compose already running** | **DENY** (concurrency = 1) |
| Machine **RED** | **DENY**, would risk a swap-thrash freeze |
| Machine **AMBER** | allow, plus inject a warning for the agent to relay |

- **Concurrency is counted live via `pgrep`, not lockfiles.** A crashed op just disappears, so
  there's no stale-lock problem.
- `DENY` is the only enforcement that survives `--dangerously-skip-permissions` (an interactive
  "proceed?" prompt can't show in bypass mode); `AMBER` warnings are model-visible context only.
- **Fail-open:** any parse/probe error means allow. A monitoring bug must never block real work.
- **Escape hatch:** prefix the command with `PRESSURE_OVERRIDE=1` to bypass the gate when you know
  what you're doing.
- Running sessions read hooks at startup, so changes apply to new sessions; existing tabs are
  unaffected until restarted.

### Configuration

All via environment variables, all optional:

| Variable | Default | Purpose |
|---|---|---|
| `PRESSURE_PROBE` | `~/.claude/pressure-monitor/pressure.sh` | Path to `pressure.sh`. Override if you install it elsewhere. |
| `PRESSURE_OVERRIDE=1` | - | Prefix on the command itself: explicit, deliberate override once you've judged it's safe to proceed anyway. |

---

## Install

1. Copy `pressure.sh` somewhere stable and make it executable:

   ```bash
   mkdir -p ~/.claude/pressure-monitor
   curl -fsSL https://raw.githubusercontent.com/dimokol/usefull-agent-skills/main/statusline/pressure.sh \
     -o ~/.claude/pressure-monitor/pressure.sh
   chmod +x ~/.claude/pressure-monitor/pressure.sh
   ```

2. Wire it into ccstatusline (see "Wiring it up" above) so the badge shows in every tab.

3. Copy the hook and make it executable:

   ```bash
   mkdir -p ~/.claude/hooks
   curl -fsSL https://raw.githubusercontent.com/dimokol/usefull-agent-skills/main/statusline/pretooluse-pressure/hook.sh \
     -o ~/.claude/hooks/pretooluse-pressure.sh
   chmod +x ~/.claude/hooks/pretooluse-pressure.sh
   ```

4. Register it in `~/.claude/settings.json` (merge with your existing hooks):

   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             { "type": "command", "command": "sh \"$HOME/.claude/hooks/pretooluse-pressure.sh\"" }
           ]
         }
       ]
     }
   }
   ```

5. If you installed `pressure.sh` somewhere other than the default path, set `PRESSURE_PROBE` in
   the same env block, or export it in your shell profile.

6. Verify: with the machine at OK/AMBER pressure, ask the agent to run `npm install`, it should
   pass (with a warning at AMBER). To see a DENY, temporarily lower `RAM_RED` in `pressure.sh` to a
   value below your current RAM %, retry, then put it back.

Requires `jq`.

---

## Related

- **Deferred:** a true blocking cross-session queue (auto-wait for a free slot rather than
  deny-and-retry). The current `pgrep`-based concurrency cap covers the high-value case (e2e/docker
  = 1) without the complexity; revisit only if deny-and-retry proves annoying in practice.
- **Deferred:** cross-platform probes (Windows/Linux). The thresholds and level logic are already
  platform-agnostic; only the five `compute()` reads in `pressure.sh` need OS-specific
  replacements (e.g. `/proc/meminfo` and `free` on Linux).
