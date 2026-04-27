#!/usr/bin/env bash
# install.sh — install skills from dimokol/usefull-agent-skills into ~/.claude/skills/
#
# Usage:
#   Install a specific skill:   bash install.sh verify-manual-tests
#   Install all skills:         bash install.sh

set -euo pipefail

REPO="https://raw.githubusercontent.com/dimokol/usefull-agent-skills/main"
SKILLS_DIR="$HOME/.claude/skills"
SKILLS_AVAILABLE=(
  "verify-manual-tests"
)

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
echo "Done. Restart Claude Code (or open a new session) to pick up new skills."
