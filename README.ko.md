# ts-graph-tools

[English](README.md) | **한국어**

[`@ttsc/graph`](https://www.npmjs.com/package/@ttsc/graph) — TypeScript **코드
그래프 MCP 서버** — 를 대상 레포에 손대지 않고 붙이기 위한 **외부 호스트**입니다.
(`@ttsc/graph`는 typia/nestia 저자 [samchon](https://github.com/samchon)의
[ttsc](https://github.com/samchon) 툴체인의 일부입니다.)

TypeScript 코드베이스를 그래프로 색인해서, `inspect_typescript_graph` 라는 MCP 툴
하나로 코딩 에이전트에 제공합니다. 그래프는 **이름·엣지·시그니처·소스 위치(span)만
반환하고 코드 본문은 안 줍니다.** 그래서 *"이거 누가 호출해?"*, *"이 흐름 따라가봐"*,
*"여기 어디서 쓰여?"* 같은 탐색을 **파일을 0개 읽고** 답합니다 (벤치마크상 토큰 ~90%,
툴콜 ~93–96% 절감). `tsc` 진단도 같은 그래프에 실려 나옵니다. tsconfig alias·재-export·
심링크를 텍스트 파서가 아니라 **실제 타입체커** 기준으로 정확히 해석합니다.

## 왜 별도 호스트 레포인가

핵심 목표는 **대상 레포를 전혀 건드리지 않고** 분석하는 것입니다:

- **그래프 엔진은 TypeScript 7 네이티브**(`typescript-go`)입니다. 일부 프로젝트는
  아직 구버전 TypeScript로 빌드됩니다(예: TypeScript 4.7에 고정된 서비스).
- 엔진을 각 대상 레포에 설치하면 그 레포의 `package.json` / `node_modules` /
  lockfile이 바뀝니다. 대신 **모든 걸 여기(호스트)에** 두고, 각 대상 프로젝트에는
  이 호스트의 바이너리를 가리키는 **로컬 스코프 MCP 등록**만 추가합니다(env 오버라이드
  2개).
- 결과: 대상 레포의 빌드 파이프라인(`nest build`, `ts-jest`, `tsc`)은 계속 자기
  TypeScript 버전을 씁니다. 그래프만 TS7을 사용합니다. **대상 레포 흔적 0** — 커밋되는
  파일도, 의존성 변경도 없음.

이건 **범용 호스트**입니다: 프로젝트마다 한 번씩 등록(붙는 대상만 다름)해서 어떤 TS
레포에든 재사용합니다.

## 여기에 설치되는 것

| 패키지 | 역할 |
|---|---|
| `@ttsc/graph@0.19.3` | MCP 서버 (`lib/bin.js`) |
| `ttsc@0.19.3` | 네이티브 **그래프 빌더** 바이너리 제공 (`@ttsc/<platform>/bin/ttscgraph`) |
| `ts7` → `typescript@7.0.2` | 네이티브 **TS7 체커** 바이너리 제공 (`@typescript/typescript-<platform>/lib/tsc`) |

> **버전 lockstep:** `ttsc`, `@ttsc/graph` (그리고 추가 시 `@ttsc/lint`)는 **모두 같은
> 버전**이어야 합니다 — `@ttsc/graph`가 `ttsc`를 정확한(exact) peer로 요구합니다.
> 그래서 `package.json`에 `^` 없이 정확히 고정했습니다.

네이티브 바이너리는 플랫폼별 **optional dependency**라, `package.json` +
`package-lock.json`을 커밋해도 cross-platform 안전합니다: Linux/CI에서 `npm install`
하면 해당 플랫폼 바이너리를 자동으로 가져옵니다. `node_modules/`는 gitignore 처리됩니다.

## 설치

```bash
git clone https://github.com/KimHG1995/ts-graph-tools.git
cd ts-graph-tools
npm install
```

그다음 대상 프로젝트의 MCP를 등록합니다 (로컬 스코프, 나만, 커밋 안 됨):

```bash
./scripts/register-mcp.sh <mcp-이름> <대상-프로젝트-경로>
```

대상 프로젝트 **안에서** Claude Code를 재시작하면 `inspect_typescript_graph` 툴이
활성화됩니다.

### 등록이 하는 일

아래와 동등합니다 (대상 프로젝트 안에서 실행):

```bash
claude mcp add <mcp-이름> --scope local \
  -e TTSC_GRAPH_BINARY="<host>/node_modules/@ttsc/<platform>/bin/ttscgraph" \
  -e TTSC_TSGO_BINARY="<host>/node_modules/@typescript/typescript-<platform>/lib/tsc" \
  -- node "<host>/node_modules/@ttsc/graph/lib/bin.js"
```

- `<host>` — 이 레포를 clone한 절대 경로.
- `<platform>` — 예: `darwin-arm64`, `linux-x64` (스크립트가 자동으로 채웁니다).
- `TTSC_TSGO_BINARY` — TS7 네이티브 체커. `resolveTsgo`가 이걸 **최우선**으로 써서,
  대상 프로젝트의 `node_modules`에서 컴파일러를 절대 찾지 않습니다.
- `TTSC_GRAPH_BINARY` — 네이티브 그래프 빌더. `resolveGraphBinary`가 최우선 사용.
- **cwd** — Claude Code가 MCP를 cwd = 프로젝트 루트로 실행하므로, 그래프가 어떤
  프로젝트(와 `tsconfig.json`)를 분석할지 결정됩니다.

두 env 경로는 절대 경로이고 모든 프로젝트에서 동일합니다. 프로젝트별 유일한 차이는
로컬 스코프 MCP가 **어느 프로젝트에 붙느냐**뿐입니다.

## 범위: graph만 (lint 제외)

`@ttsc/lint`는 MCP 서버가 아니라 **컴파일 플러그인**이고, 룰을 켜려면 대상 레포 **안에**
`lint.config.ts`가 있어야 합니다 — 그래서 흔적 0으로는 호스팅할 수 없습니다. 이 호스트는
**graph만** 다룹니다.

## 검증

```bash
# 어떤 프로젝트든 건드리지 않고 그래프 덤프:
node_modules/.bin/ttscgraph dump \
  --cwd <대상-프로젝트-경로> \
  --tsconfig tsconfig.json > /dev/null && echo OK
```
