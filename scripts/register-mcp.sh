#!/usr/bin/env bash
#
# Register the @ttsc/graph MCP server for a target TypeScript project.
#
# The graph engine (TS7 native) and the graph builder live HERE, in this host
# repo. The MCP is registered at *local* scope for the target project, so the
# target repo stays completely untouched (no package.json / node_modules /
# .mcp.json changes). Claude Code launches the MCP with cwd = the project root,
# and the two env overrides point the engine at this host's binaries.
#
# Usage:
#   ./scripts/register-mcp.sh <mcp-name> <project-dir>
#
# Example:
#   ./scripts/register-mcp.sh ttsc-graph-cmes /Users/hgkim/Documents/KPEC/cmes-server
#
# Requires the `claude` CLI on PATH. Run it, then restart Claude Code inside the
# target project to pick up the `inspect_typescript_graph` tool.

set -euo pipefail

HOST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NAME="${1:?usage: register-mcp.sh <mcp-name> <project-dir>}"
PROJ_IN="${2:?usage: register-mcp.sh <mcp-name> <project-dir>}"
PROJ="$(cd "$PROJ_IN" && pwd)"

# Resolve the platform-specific native binary directory names.
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)   TTSC_PLAT="darwin-arm64" ; TS_PLAT="darwin-arm64" ;;
  Darwin-x86_64)  TTSC_PLAT="darwin-x64"   ; TS_PLAT="darwin-x64"   ;;
  Linux-x86_64)   TTSC_PLAT="linux-x64"    ; TS_PLAT="linux-x64"    ;;
  Linux-aarch64)  TTSC_PLAT="linux-arm64"  ; TS_PLAT="linux-arm64"  ;;
  *) echo "unsupported platform: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

GRAPH_JS="$HOST/node_modules/@ttsc/graph/lib/bin.js"
GRAPH_BIN="$HOST/node_modules/@ttsc/${TTSC_PLAT}/bin/ttscgraph"
TSGO_BIN="$HOST/node_modules/@typescript/typescript-${TS_PLAT}/lib/tsc"

for f in "$GRAPH_JS" "$GRAPH_BIN" "$TSGO_BIN"; do
  if [[ ! -e "$f" ]]; then
    echo "missing: $f" >&2
    echo "run 'npm install' in $HOST first." >&2
    exit 1
  fi
done

echo "Registering MCP '$NAME' (local scope) for project:"
echo "  $PROJ"
echo "  graph builder : $GRAPH_BIN"
echo "  TS7 engine    : $TSGO_BIN"

# Local scope attaches to the current directory's project, so register from
# inside the target project.
cd "$PROJ"
claude mcp add "$NAME" --scope local \
  -e "TTSC_GRAPH_BINARY=$GRAPH_BIN" \
  -e "TTSC_TSGO_BINARY=$TSGO_BIN" \
  -- node "$GRAPH_JS"

echo
echo "Done. Restart Claude Code inside $PROJ to use inspect_typescript_graph."
