# ts-graph-tools

**English** | [한국어](README.ko.md)

External host for [`@ttsc/graph`](https://www.npmjs.com/package/@ttsc/graph) — a
TypeScript **code-graph MCP server** (from the [ttsc](https://github.com/samchon)
toolchain by samchon, author of typia/nestia).

It indexes a TypeScript codebase into a graph and exposes it to a coding agent
through one MCP tool, `inspect_typescript_graph`. The graph returns **names,
edges, signatures, and source spans — not file bodies** — so questions like *"who
calls this?"*, *"trace this flow"*, *"where is this used?"* are answered by
reading **zero files** (benchmarks: ~90% fewer tokens, ~93–96% fewer tool calls).
`tsc` diagnostics ride along on the same graph. tsconfig aliases, re-exports, and
symlinks are resolved by the **real type checker**, not a text parser.

## Why a separate host repo

The whole point is to analyze a target repo **without touching it**:

- The **graph engine is TypeScript 7 native** (`typescript-go`). Some projects
  still build on older TypeScript (e.g. a service still pinned to TypeScript 4.7).
- Installing the engine into each target repo would change its `package.json` /
  `node_modules` / lockfile. Instead, everything lives **here**, and each target
  project gets a **local-scope MCP registration** pointing at this host's binaries
  via two env overrides.
- Result: the target repo's build pipeline (`nest build`, `ts-jest`, `tsc`) keeps
  using its own TypeScript version. Only the graph uses TS7. **Zero footprint** on
  the target — no committed files, no dependency changes.

This is a **general host**: register it once per project (differing only by which
project it's attached to), reuse across any TS repo.

## What's installed here

| Package | Role |
|---|---|
| `@ttsc/graph@0.19.3` | The MCP server (`lib/bin.js`) |
| `ttsc@0.19.3` | Brings the native **graph builder** binary (`@ttsc/<platform>/bin/ttscgraph`) |
| `ts7` → `typescript@7.0.2` | Brings the native **TS7 checker** binary (`@typescript/typescript-<platform>/lib/tsc`) |

> **Version lockstep:** `ttsc`, `@ttsc/graph` (and `@ttsc/lint`, if ever added)
> must share the same version — `@ttsc/graph` declares `ttsc` as an exact peer.
> Pinned exactly (no `^`) in `package.json` for this reason.

The native binaries are per-platform **optional dependencies**, so committing
`package.json` + `package-lock.json` is cross-platform safe: `npm install` on
Linux/CI fetches that platform's binaries automatically. `node_modules/` is
gitignored.

## Setup

```bash
git clone https://github.com/KimHG1995/ts-graph-tools.git
cd ts-graph-tools
npm install
```

Then register a target project's MCP (local scope, private to you, not committed):

```bash
./scripts/register-mcp.sh <mcp-name> <path-to-target-project>
```

Restart Claude Code **inside the target project** to pick up the
`inspect_typescript_graph` tool.

### What the registration does

Equivalent to (run from inside the target project):

```bash
claude mcp add <mcp-name> --scope local \
  -e TTSC_GRAPH_BINARY="<host>/node_modules/@ttsc/<platform>/bin/ttscgraph" \
  -e TTSC_TSGO_BINARY="<host>/node_modules/@typescript/typescript-<platform>/lib/tsc" \
  -- node "<host>/node_modules/@ttsc/graph/lib/bin.js"
```

- `<host>` — the absolute path where you cloned this repo.
- `<platform>` — e.g. `darwin-arm64`, `linux-x64` (the script fills this in).
- `TTSC_TSGO_BINARY` — the TS7 native checker. `resolveTsgo` uses it **first**, so
  the target project's `node_modules` is never consulted for the compiler.
- `TTSC_GRAPH_BINARY` — the native graph builder. `resolveGraphBinary` uses it first.
- **cwd** — Claude Code launches the MCP with cwd = the project root, which is how
  the graph knows which project (and `tsconfig.json`) to analyze.

Both env paths are absolute and identical for every project; the only per-project
difference is which project the local-scope MCP is attached to.

## Scope: graph only (not lint)

`@ttsc/lint` is a **compile plugin**, not an MCP server, and it requires a
`lint.config.ts` **inside** the target repo to activate its rules — so it can't be
hosted here with zero footprint. This host covers **graph** only.

## Verify

```bash
# Dump a graph for any project without touching it:
node_modules/.bin/ttscgraph dump \
  --cwd <path-to-target-project> \
  --tsconfig tsconfig.json > /dev/null && echo OK
```
