#!/usr/bin/env bash
# install.sh — install skills from dimokol/usefull-agent-skills into an agent skills dir.
#
# Usage:
#   Install a specific skill:   bash install.sh verify-manual-tests
#   Install all skills:         bash install.sh
#   Install for Codex:          SKILLS_DIR="$HOME/.codex/skills" bash install.sh

set -euo pipefail

REPO="https://raw.githubusercontent.com/dimokol/usefull-agent-skills/main"
SKILLS_DIR="${SKILLS_DIR:-$HOME/.claude/skills}"
SKILLS_AVAILABLE=(
  "babysit-prs"
)
# Note: `verify-manual-tests` is deprecated — superseded by deterministic
# Playwright e2e specs (`npm run test:e2e:full`). It is NOT installed by
# default but can still be fetched explicitly via `bash install.sh verify-manual-tests`
# if you want to read the tombstone.

install_skill() {
  local skill="$1"
  local dest="$SKILLS_DIR/$skill"
  mkdir -p "$dest"
  echo "Installing $skill..."
  curl -fsSL "$REPO/skills/$skill/SKILL.md" -o "$dest/SKILL.md"
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
