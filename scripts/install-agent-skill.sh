#!/usr/bin/env bash
# Link the canonical skill into a client's user-level discovery directory.
set -euo pipefail

usage() {
  echo "usage: bash scripts/install-agent-skill.sh <claude|codex> [skills-directory]"
}

if [[ "$#" -eq 1 && "$1" == "--help" ]]; then
  usage
  exit 0
fi
if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
  usage >&2
  exit 2
fi
case "$1" in
  claude) GRAPH_SKILLS_DIR="${2-${HOME:?HOME must be set}/.claude/skills}" ;;
  codex) GRAPH_SKILLS_DIR="${2-${HOME:?HOME must be set}/.agents/skills}" ;;
  *) usage >&2; exit 2 ;;
esac
if [[ -z "$GRAPH_SKILLS_DIR" ]]; then
  usage >&2
  exit 2
fi

GRAPH_HOST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
GRAPH_SKILL_SOURCE="$GRAPH_HOST_DIR/skills/ts-graph"
if [[ ! -f "$GRAPH_SKILL_SOURCE/SKILL.md" ]]; then
  echo "missing skill: $GRAPH_SKILL_SOURCE/SKILL.md" >&2
  exit 1
fi

mkdir -p -- "$GRAPH_SKILLS_DIR"
GRAPH_SKILLS_DIR="$(cd "$GRAPH_SKILLS_DIR" && pwd -P)"
GRAPH_SKILL_TARGET="$GRAPH_SKILLS_DIR/ts-graph"
if [[ -L "$GRAPH_SKILL_TARGET" && "$(readlink "$GRAPH_SKILL_TARGET")" == "$GRAPH_SKILL_SOURCE" ]]; then
  echo "already installed: $GRAPH_SKILL_TARGET"
  exit 0
fi
if [[ -e "$GRAPH_SKILL_TARGET" || -L "$GRAPH_SKILL_TARGET" ]]; then
  echo "refusing to replace existing path: $GRAPH_SKILL_TARGET" >&2
  exit 1
fi

ln -s -- "$GRAPH_SKILL_SOURCE" "$GRAPH_SKILL_TARGET"
echo "installed: $GRAPH_SKILL_TARGET -> $GRAPH_SKILL_SOURCE"
echo "Skill only; register the MCP separately. Keep this host checkout at its current path."
