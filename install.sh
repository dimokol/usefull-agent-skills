#!/usr/bin/env bash
# install.sh — install skills from dimokol/usefull-agent-skills into an agent skills dir.
#
# Usage:
#   Install a specific skill:   bash install.sh babysit-prs
#   Install all skills:         bash install.sh
#   Install for Codex:          SKILLS_DIR="$HOME/.codex/skills" bash install.sh

set -euo pipefail

REPO="https://raw.githubusercontent.com/dimokol/usefull-agent-skills/main"
SKILLS_DIR="${SKILLS_DIR:-$HOME/.claude/skills}"
SKILLS_AVAILABLE=(
  "babysit-prs"
  "create-pr"
  "e2e-harness-patterns"
  "setup-audit"
  "task-sync"
  "verify-before-building"
  "worktree-hygiene"
  "worktree-qa-queue"
)

# When run from a local clone (not the `curl | bash` one-liner), prefer the
# checked-out SKILL.md over a remote fetch — this makes `bash install.sh`
# pick up skills that were only just added locally and not pushed to `main`
# yet, without changing behavior for the piped remote install.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""

install_skill() {
  local skill="$1"
  local dest="$SKILLS_DIR/$skill"
  local local_file="$SCRIPT_DIR/skills/$skill/SKILL.md"
  mkdir -p "$dest"
  echo "Installing $skill..."
  if [[ -n "$SCRIPT_DIR" && -f "$local_file" ]]; then
    cp "$local_file" "$dest/SKILL.md"
  else
    curl -fsSL "$REPO/skills/$skill/SKILL.md" -o "$dest/SKILL.md"
  fi
  echo "  -> $dest/SKILL.md"
}

if [[ $# -eq 0 ]]; then
  echo "Installing all skills..."
  for skill in "${SKILLS_AVAILABLE[@]}"; do
    install_skill "$skill"
  done
else
  install_skill "$1"
fi

echo ""
echo "Done. Restart your agent (or open a new session) to pick up new skills."
