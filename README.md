# ts-graph-tools

**English** | [한국어](README.ko.md)

External host for [`@ttsc/graph`](https://www.npmjs.com/package/@ttsc/graph) — a
TypeScript **code-graph MCP server** (from the [ttsc](https://github.com/samchon)
toolchain by samchon, author of typia/nestia).

The `@ttsc/graph` server running in this host indexes a TypeScript codebase and
exposes the result through one MCP tool, `inspect_typescript_graph`. It returns
**names, edges, signatures, and source spans rather than file bodies**. Questions
about callers, flows, and usages can therefore obtain graph facts without reading
source bodies directly. End-to-end token and latency effects still depend on the
task and model and are measured separately in `agent-bench`. `tsc` diagnostics
are included in the same graph result. `@ttsc/graph` resolves tsconfig aliases,
re-exports, and symlink relationships through the TypeScript checker rather than
plain text search.

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

This is intended as a **reusable external host** for TypeScript repositories.
Each project gets its own local MCP registration while reusing the same host
binaries.

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

## Usage — the `inspect_typescript_graph` tool

Once registered, the host exposes a **single MCP tool**, `inspect_typescript_graph`.
You don't call it by hand — ask Claude a question about the codebase in plain
language and it selects and submits one request. The names, edges, signatures, and spans returned by `@ttsc/graph` are based on
compiler-resolved information. They are useful directly for relationship queries
such as callers and callees, while questions that depend on source-body text or
non-TypeScript files still require file inspection.

### Request envelope (chain of thought)

Each call carries a short reasoning plus exactly one request:

| Field | Meaning |
|---|---|
| `question` | the code question in the user's own words — the graph ranks against these exact words |
| `draft` | `{ reason, type }`: the smallest request that could answer, and why |
| `review` | correct the draft; escape if the graph already answered or the evidence is outside it |
| `request` | the final request — exactly one of the seven types below |

The result carries an `audit` (what was verified) and a `next` hint —
`answer` / `inspect` / `outside` / `clarify` — that paces any follow-up.

### The seven request types (methods)

| Type | Answers | Key inputs |
|---|---|---|
| `tour` | Architecture, runtime flow, orientation — a whole code tour in one call | `reinterpretations[]` (symbol names you expect, or `[]`), `limit` |
| `entrypoints` | Where execution starts, when the entry point is unknown | `query`, `limit` |
| `lookup` | Locate a named symbol (where it's declared) | `query`, `limit` |
| `trace` | Follow calls / data flow, or the path A→B | `from`, `to?`, `direction`, `focus` |
| `details` | Signatures, members, and **what implements an interface** | `handles[]`, `neighbors?`, `memberLimit?` |
| `overview` | Project layers, folders, hotspots, public API | `aspect` |
| `escape` | The answer is **outside** the graph (source body text, non-TS files, exact string search) | `reason` |

#### Parameter notes

- `trace.direction`: `forward` = what the start uses (callees) · `reverse` = what uses it (callers) · `impact` = reverse trace prioritizing public API + the tests a change reaches.
- `trace.focus`: `execution` (runtime calls/instantiations/JSX) · `types` (type refs/inheritance) · `all`.
- `trace.to`: when both ends are known, returns the path between them — the one call for *"how does A reach B"*.
- `details` returns an interface's implementers — the one call for *"what actually implements this"*.
- Ranked ops (`lookup`, `entrypoints`, `tour`) return a scored, capped shortlist: the facts are verified, but whether the shortlist covers your question is yours to judge.

### Example questions → the method it picks

| You ask | Method |
|---|---|
| "Give me a tour of this server's architecture and main flow" | `tour` |
| "Where does payment processing start?" | `entrypoints` |
| "Where is `OrderService.create` declared?" | `lookup` |
| "Who calls this function?" | `trace` (reverse) |
| "How does the controller reach the repository?" | `trace` (with `to`) |
| "Which classes implement this interface?" | `details` |
| "Show the folder layers and the public API" | `overview` |

## Coding agent skill

The canonical usage workflow is [skills/ts-graph/SKILL.md](skills/ts-graph/SKILL.md).
The MCP server supplies graph facts; the skill explains project selection,
request routing, source-reading boundaries, incomplete results, and fallback when
no graph tool is available. It works with the connected tool's schema rather than
hard-coding a client-specific MCP server name.

Install the same source for either local client from this host checkout:

```bash
bash scripts/install-agent-skill.sh codex
bash scripts/install-agent-skill.sh claude
```

| Client | Skill discovery | MCP connection |
|---|---|---|
| Codex | User symlink at `~/.agents/skills/ts-graph` | Configure the MCP separately for the target project |
| Claude Code | User symlink at `~/.claude/skills/ts-graph` | Use `scripts/register-mcp.sh` as described above |
| ChatGPT | Package the same skill in a plugin | Connect the server separately through HTTPS or Secure MCP Tunnel |

The installer creates an absolute directory symlink to the canonical skill. It
requires Bash and standard Unix utilities, creates no files in target projects,
and does not install dependencies or register an MCP. Running it again for the
same link is a no-op. Existing files, directories, and other symlinks are rejected
without replacement. An optional second argument selects a different skills
directory, for example `bash scripts/install-agent-skill.sh codex /tmp/skill-check`.

Keep the host checkout at the same path: updating its skill updates both local
clients through their links. If you move the checkout, remove only the old skill
symlink and reinstall. To uninstall, remove only the symlink printed by the
installer. Reload the client's skill list or restart the client if it does not
show `ts-graph`. A skill by itself does not make an MCP tool available.

ChatGPT packaging and connection remain manual; this repository does not provide
a ChatGPT installer or HTTP adapter. Secure MCP Tunnel can connect to a stdio
server where available, so a new HTTP adapter is not always required. A local
Claude/Codex symlink does not install the skill into a ChatGPT account.

See the current client documentation for [Codex skill discovery](https://learn.chatgpt.com/docs/build-skills),
[Claude Code skills](https://code.claude.com/docs/en/skills), and
[ChatGPT plugin connections](https://developers.openai.com/plugins/deploy/connect-chatgpt).

To verify the installer without changing user settings (Python 3 standard library):

```bash
bash -n scripts/install-agent-skill.sh
python3 -m unittest discover -s tests -p 'test_*.py'
```

## Scope: graph only (not lint)

`@ttsc/lint` is a **compile plugin**, not an MCP server, and it requires a
`lint.config.ts` **inside** the target repo to activate its rules — so it can't be
hosted here with zero footprint. This host covers **graph** only.

## CLI & verify

The native builder runs directly from this host — env-free, still zero-footprint
on the target (`<platform>` is e.g. `darwin-arm64`, `linux-x64`):

```bash
# Smoke test — build the graph and discard it:
node_modules/@ttsc/<platform>/bin/ttscgraph dump \
  --cwd <path-to-target-project> --tsconfig tsconfig.json > /dev/null && echo OK

# Full graph as JSON (every node/edge, no MCP response caps):
node_modules/@ttsc/<platform>/bin/ttscgraph dump \
  --cwd <path-to-target-project> --tsconfig tsconfig.json --pretty > graph.json
```

`ttscgraph serve` is the internal incremental protocol the MCP server drives — not
run by hand.

## License

[Unlicense](LICENSE) — public domain. Do whatever you want; no attribution
required, no warranty. The npm packages this repo installs keep their own
licenses; none of them are vendored here.
