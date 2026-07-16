#!/bin/sh
# pressure: cheap machine-pressure probe for multi-agent laptop work.
#
# Single source of truth for resource thresholds. Consumed by:
#   - ccstatusline widgets (every tab, every ~10s)  -> --field <name> (per-segment)
#   - the PreToolUse RED-block hook (pretooluse-pressure/hook.sh in this hub) -> --json
#   - ad-hoc self-checks before heavy work         -> --json
#   - any other consumer that wants a live snapshot (e.g. your own dashboard)
#
# A 4s on-disk cache lets the per-segment statusline widgets in a single
# render share ONE sample (only the first recomputes; the rest read the cache).
#
# Modes:
#   (none)            human one-liner
#   --json            machine-readable
#   --statusline      full single-line badge
#   --field NAME      one colored segment: cpu | ram | swap | load | disk | verdict
#
# Levels: OK | AMBER | RED   (overall = worst of any signal)
# Full reference: this area's README.md (statusline/README.md)
#
# macOS only today (vm_stat / sysctl / df). Cross-platform (Windows/Linux)
# probes are a TODO, see the README's portability note.

set -u

CACHE="/tmp/pressure-monitor.cache"
TTL=4

# ---- thresholds (the one place to tune) ----
CPU_AMBER=85;   CPU_RED=97        # % CPU (recent decaying avg across procs / cores)
RAM_AMBER=85;   RAM_RED=93        # % RAM used (low available)
SWAP_AMBER=70;  SWAP_RED=90       # % of swap used
LOAD_AMBER=12;  LOAD_RED=24       # 1-min load (8-core laptop: 1.5x / 3x, tune for your core count)
DISK_AMBER=20;  DISK_RED=10       # GB free on /

compute() {
  swap_line=$(sysctl -n vm.swapusage 2>/dev/null || echo "total = 1.00M used = 0.00M free = 1.00M")
  swap_total=$(printf '%s\n' "$swap_line" | sed -n 's/.*total = \([0-9.][0-9.]*\)M.*/\1/p')
  swap_used=$(printf '%s\n' "$swap_line" | sed -n 's/.*used = \([0-9.][0-9.]*\)M.*/\1/p')
  swap_free_mb=$(printf '%s\n' "$swap_line" | sed -n 's/.*free = \([0-9.][0-9.]*\)M.*/\1/p')

  load1=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2+0}')
  disk_free=$(df -g / 2>/dev/null | awk 'NR==2{print $4+0}')
  cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 8)
  mem_total_mb=$(awk -v b="$(sysctl -n hw.memsize 2>/dev/null || echo 0)" 'BEGIN{printf "%d", b/1048576}')

  # CPU: sum of per-process %cpu (a recent ~1-min decaying average) / cores, capped.
  # Instant (no sampling wait), lags a sudden spike but cheap enough for every render.
  cpu_pct=$(ps -A -o %cpu= 2>/dev/null | awk -v c="${cores:-8}" '{s+=$1} END{v=(c>0)?s/c:s; if(v>100)v=100; printf "%d", v}')

  # available RAM ~= (free + inactive + speculative + purgeable) pages * pagesize
  avail_mb=$(vm_stat 2>/dev/null | awk '
    /page size of/      { match($0,/[0-9]+/); pg=substr($0,RSTART,RLENGTH) }
    /Pages free/        { gsub(/\./,""); f=$3 }
    /Pages inactive/    { gsub(/\./,""); i=$3 }
    /Pages speculative/ { gsub(/\./,""); s=$3 }
    /Pages purgeable/   { gsub(/\./,""); p=$3 }
    END { if(pg=="")pg=16384; printf "%d", (f+i+s+p)*pg/1048576 }')

  swap_pct=$(awk -v u="${swap_used:-0}" -v t="${swap_total:-1}" 'BEGIN{ printf "%d", (t<=0)?0:(u/t)*100 }')
  ram_pct=$(awk -v a="${avail_mb:-0}" -v t="${mem_total_mb:-1}" 'BEGIN{ printf "%d", (t<=0)?0:(1-(a/t))*100 }')
  load1=${load1:-0}; disk_free=${disk_free:-0}; swap_free_mb=${swap_free_mb:-0}; cpu_pct=${cpu_pct:-0}

  s_cpu=$(awk  -v v="$cpu_pct"  -v a="$CPU_AMBER"  -v r="$CPU_RED"  'BEGIN{print (v>=r)?2:(v>=a)?1:0}')
  s_swap=$(awk -v v="$swap_pct" -v a="$SWAP_AMBER" -v r="$SWAP_RED" 'BEGIN{print (v>=r)?2:(v>=a)?1:0}')
  s_ram=$(awk  -v v="$ram_pct"  -v a="$RAM_AMBER"  -v r="$RAM_RED"  'BEGIN{print (v>=r)?2:(v>=a)?1:0}')
  s_load=$(awk -v v="$load1"    -v a="$LOAD_AMBER" -v r="$LOAD_RED" 'BEGIN{print (v>=r)?2:(v>=a)?1:0}')
  s_disk=$(awk -v v="$disk_free" -v a="$DISK_AMBER" -v r="$DISK_RED" 'BEGIN{print (v<=r)?2:(v<=a)?1:0}')

  worst=$s_cpu
  for x in $s_ram $s_swap $s_load $s_disk; do [ "$x" -gt "$worst" ] && worst=$x; done

  # atomic cache write (shared safely across tabs)
  tmp="$CACHE.$$"
  {
    echo "cpu_pct=$cpu_pct"; echo "swap_pct=$swap_pct"; echo "ram_pct=$ram_pct"; echo "load1=$load1"
    echo "disk_free=$disk_free"; echo "swap_free_mb=$swap_free_mb"; echo "cores=$cores"
    echo "s_cpu=$s_cpu"; echo "s_swap=$s_swap"; echo "s_ram=$s_ram"; echo "s_load=$s_load"; echo "s_disk=$s_disk"; echo "worst=$worst"
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$CACHE" 2>/dev/null
}

load_or_compute() {
  if [ -f "$CACHE" ]; then
    now=$(date +%s); m=$(stat -f %m "$CACHE" 2>/dev/null || echo 0)
    age=$(( now - m ))
    if [ "$age" -ge 0 ] && [ "$age" -lt "$TTL" ] && . "$CACHE" 2>/dev/null; then
      return 0
    fi
  fi
  compute
}

load_or_compute

case "$worst" in
  2) level=RED;   verdict="heavy ops blocked"; icon="⛔" ;;
  1) level=AMBER; verdict="caution";           icon="⚠"  ;;
  *) level=OK;    verdict="clear";             icon="✅" ;;
esac

RST=$(printf '\033[0m')
col_for() { case "$1" in 2) printf '\033[31m';; 1) printf '\033[33m';; *) printf '\033[32m';; esac; }
sw=""; [ "${s_swap:-0}" -ge 1 ] && sw="▲"

case "${1:-}" in
  --json)
    printf '{"level":"%s","verdict":"%s","cpu_pct":%s,"ram_pct":%s,"swap_pct":%s,"swap_free_mb":%s,"load1":%s,"disk_free_gb":%s,"cores":%s}\n' \
      "$level" "$verdict" "$cpu_pct" "$ram_pct" "$swap_pct" "$swap_free_mb" "$load1" "$disk_free" "${cores:-8}"
    ;;
  --statusline)
    c=$(col_for "$worst")
    printf '%s🖥 CPU %s%%·RAM %s%%·swap %s%%%s·load %s·disk %sG  %s %s%s\n' \
      "$c" "$cpu_pct" "$ram_pct" "$swap_pct" "$sw" "$load1" "$disk_free" "$icon" "$verdict" "$RST"
    ;;
  --field)
    case "${2:-}" in
      cpu)     printf '%sCPU %s%%%s'   "$(col_for "$s_cpu")"  "$cpu_pct"  "$RST" ;;
      ram)     printf '%sRAM %s%%%s'   "$(col_for "$s_ram")"  "$ram_pct"  "$RST" ;;
      swap)    printf '%sswap %s%%%s%s' "$(col_for "$s_swap")" "$swap_pct" "$sw" "$RST" ;;
      load)    printf '%sload %s%s'    "$(col_for "$s_load")" "$load1"    "$RST" ;;
      disk)    printf '%sdisk %sG%s'   "$(col_for "$s_disk")" "$disk_free" "$RST" ;;
      verdict) printf '%s%s %s%s'      "$(col_for "$worst")"  "$icon" "$verdict" "$RST" ;;
      *) : ;;
    esac
    ;;
  *)
    printf '%s | CPU %s%% | RAM %s%% | swap %s%% (%sMB free) | load %s | disk %sGB free | %s\n' \
      "$level" "$cpu_pct" "$ram_pct" "$swap_pct" "$swap_free_mb" "$load1" "$disk_free" "$verdict"
    ;;
esac
