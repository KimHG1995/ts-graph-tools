---
name: ts-graph
description: Use when locating TypeScript symbols, tracing callers or execution paths, finding interface implementations, or exploring architecture with inspect_typescript_graph.
---

# TypeScript code graph

Use the available `inspect_typescript_graph` MCP tool to narrow structural
TypeScript questions before reading whole files. This skill supplies a workflow;
it does not install or register the server.

## Select the project

Use the server registered for the user's target repository. When several servers
expose the tool, use registration and working-directory evidence to select one;
the server name alone does not establish its target. Check the returned project
on the first useful query. If it differs, select the correct server before using
the result. If the target remains ambiguous, ask for the missing project context.

If the tool is unavailable or fails, use scoped source searches and reads and
state that limitation. Do not change dependencies or MCP settings just to answer
a code question.

## Choose the smallest useful request

Use the connected tool's schema for the request envelope and supported inputs.
Keep required rationale fields brief and task-focused.

| Question | Request |
|---|---|
| Architecture or a runtime-flow tour | `tour` |
| Unknown execution starting point | `entrypoints` |
| Symbol location or ambiguous name | `lookup` |
| Callers / callees | `trace` with `reverse` / `forward` |
| Path from A to B | `trace` with `from` and `to` |
| Change impact in the current source | `trace` with `direction: impact` |
| Signatures, members, interface implementations | `details` |
| Folder layers or project shape | `overview` |

Reuse returned symbol handles for follow-up requests. For example, to answer
"Who calls OrderService.create?", select the project's server and request a
reverse execution trace; use `lookup` first if the symbol is ambiguous.

## Use the evidence within its limits

Answer relationship questions from returned symbols, edges, and source spans,
citing file locations. Avoid rereading whole files merely to repeat a relationship
the graph already supplies. Use `audit`, `next`, and truncation information to
decide whether to answer, make a focused follow-up, or inspect source.

A ranked shortlist or bounded trace does not establish that an omitted caller or
path is absent. Static graph coverage also does not prove all dynamic runtime
behavior. State unresolved coverage and investigate only what the question needs.
After source edits, obtain fresh graph evidence before relying on earlier relations.

## Read source when the task needs it

Read relevant source bodies before editing. Use source directly for algorithms,
conditions, SQL, exact strings, comments, configuration, and non-TypeScript files.
A known-file text edit does not need a preliminary graph query. `escape` can mark
a transition out of an existing graph exchange; it is not a prerequisite to read.

Use Git or available sem tools for diffs, history, and blame. Add graph queries
only when current TypeScript relationships are also needed; avoid duplicate
impact queries without an evidence gap. Follow the target repository's normal
validation requirements after changes.
