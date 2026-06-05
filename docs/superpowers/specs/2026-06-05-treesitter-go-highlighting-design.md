# Real Tree-sitter Syntax Highlighting (Go first)

Date: 2026-06-05
Status: Approved design — ready for implementation planning

## Summary

ArchSight's Phase 4 syntax pipeline currently emits only naive `keyword` tokens
from an identifier scanner (`core/internal/syntax/syntax.go`), and the macOS
client never renders those tokens — `CodeTextView` shows plain monospaced text.

This work replaces the Go highlighting path with a real Tree-sitter pipeline and
makes highlighting visible in the UI. It is the first slice of the Tree-sitter
integration the work plan deferred ("create the adapter with one language first
if grammar packaging needs staging"). Only **Go** is converted in this slice;
Swift, TypeScript, and Markdown keep their current behavior and are expanded
later through the same path.

Tree-sitter runs **without CGo**, via `github.com/malivvan/tree-sitter`, a
cgo-free wrapper that embeds a Wasm build of tree-sitter (v0.24.7) and runs it on
the `wazero` pure-Go runtime. This preserves ArchSight's single static Go binary
and its low-memory / simple-packaging premise.

## Goals

- Replace the Go keyword scanner with real Tree-sitter parsing + highlight
  queries, producing accurate token spans for keywords, strings, comments,
  numbers, functions, types, etc.
- Render those tokens as colors in the read-only macOS code viewer, following
  system light/dark appearance.
- Keep the IPC token schema unchanged (backward compatible).
- Keep the pure-Go single-binary build, lazy/idle memory behavior, read-only
  product boundary, and "no child processes" guarantees intact.

## Non-Goals

- Tree-sitter highlighting for Swift / TypeScript / Markdown (next slice). Their
  grammars are NOT in the shipped Wasm, so that slice must first rebuild the Wasm
  via the binding's `_gen` toolchain (needs a C/Wasm toolchain), then add each
  language's highlight query.
- Semantic highlighting beyond what `highlights.scm` queries provide (no LSP
  semantic tokens, no type inference).
- Slimming the bundled Wasm to only the Go grammar (tracked tradeoff; deferred).
- Any editing, formatting, code actions, or diagnostics.

## Background / Current State

- `core/internal/syntax/syntax.go`: `Highlight(path, content) Result` detects
  language by extension (`go`, `swift`, `typescript`, `markdown`) and emits
  `keyword`-only tokens via `keywordTokens`. Unsupported extensions return an
  empty token list with empty language (plain text).
- IPC `openFile` returns `OpenFileResult{..., language, content, tokens}`.
- Swift `OpenFileResult`/`SyntaxToken` (`apps/macos/Sources/ArchSightKit/IPC.swift`)
  decode `tokens`, but `CodeTextView.swift` only does `textView.string = content`.
  **No token is ever rendered today.**
- Core is pure Go (`go 1.25`), single static binary, no CGo. Idle RSS budget
  `M <= 50MB` (currently ~12MB), enforced by `scripts/perf-gate.sh`.

## Dependency: `github.com/malivvan/tree-sitter`

Verified facts (commit `46b39a7`, 2025-01-25), confirmed by a working PoC that
parses Go and runs a highlight query end-to-end:

- cgo-free; wraps tree-sitter Wasm (`Version = v0.24.7`) on `wazero`.
- **Version pinning is non-obvious.** The only tagged release, **`v0.0.1`,
  embeds a Wasm with ONLY C and C++** (`LanguageC`/`LanguageCpp`; no Go). Go
  support and the by-name `ts.Language("go")` API live on an **untagged `main`
  commit**. We therefore pin the pseudo-version
  **`v0.0.2-0.20250125152656-46b39a70b658`** (commit `46b39a7`) in `go.mod`.
- The pinned commit's `lib/ts.wasm.br` (brotli, **1.5 MB**, `go:embed`-ed)
  carries the tree-sitter runtime and ~22 grammars **including `go`** — the
  language name is `"go"` (`ts.Language("go")`), not `"golang"`.
  **`swift`, `typescript`, and `markdown` are NOT in this shipped Wasm** — their
  grammar *sources* exist in the repo but were not compiled into `ts.wasm.br`.
- Full query engine present (`NewQuery`, `QueryCursor`, `QueryCapture`,
  `CaptureNameForID`) — this is what drives `.scm`-based highlighting.
- API at this commit takes **no `context.Context`** (e.g. `sitter.New(nil, nil)`,
  `ts.Language("go")`, `parser.ParseString(content)`, `qc.NextMatch()`). (The
  released v0.0.1 API differs — it threads `context.Context`. We code against the
  pinned commit's API.)
- Direct deps only: `github.com/andybalholm/brotli`, `github.com/tetratelabs/wazero`
  (both pure Go). Requires Go 1.23.4+ (ArchSight is on Go 1.25).
- **No `.scm` highlight queries are bundled** (`find . -name '*.scm'` → 0). We
  vendor `tree-sitter-go`'s `queries/highlights.scm` (grammar commit
  `7cb21a65af6cc8e5c6742b9dba42881ea1158475`) ourselves.
- **Pre-release, untagged commit**: elevated churn risk. Mitigation: the exact
  pseudo-version is pinned, and the binding is isolated behind the `syntax`
  package so it can be swapped without touching callers.

### Decisions (approved)

- (a) Non-Go languages keep the existing keyword adapter (no regression); other
  extensions stay plain text.
- (b) Token `type` vocabulary is the standardized set below.
- (c) Accept the +1.5 MB binary growth (bundled unused grammars) for now; Wasm
  slimming is deferred until the language set is finalized.

## Architecture

### Core syntax pipeline (`core/internal/syntax`)

The package keeps its public surface (`Highlight`, `DetectLanguage`, `Token`,
`Result`) so callers and the IPC schema are unchanged. Internals are split for
clarity and testability:

- `syntax.go` — `Highlight`, `DetectLanguage`, `Result`, `Token` (unchanged
  signatures). `Highlight` routes Go to the Tree-sitter highlighter; everything
  else to the existing keyword/plain-text behavior.
- `treesitter.go` — Tree-sitter engine wrapper:
  - **Fresh instance per highlight call.** Each `highlightGo` call does
    `sitter.New(nil, nil)`, loads `go`, compiles the query, parses, queries, then
    drops the instance (and `Close()`s the parser). The library caches the
    *compiled* Wasm module process-globally via its own `sync.Once`, so only the
    **first** highlight in the process pays the decompress+compile cost
    (~90 ms, measured); subsequent calls are ~6–13 ms each (measured). Nothing is
    instantiated at process start, so startup latency and pre-open idle RSS are
    unchanged.
  - **Why not a shared reused instance:** the pinned binding exposes no
    `Close`/free for `Tree`/`QueryCursor`/module, so reusing one instance leaks
    Wasm linear memory and **traps (`wasm error: unreachable`) after ~270 parses
    of a 4 KB file** (measured). A fresh per-call instance keeps memory bounded
    (500 sequential highlights ran with flat ~10 ms latency, no trap) because the
    anonymous module is reclaimed after each call. No mutex is needed — there is
    no shared mutable engine, and `sitter.New` / `wazero` instantiation is safe to
    call concurrently (the global compile is guarded by the library's `sync.Once`).
  - `highlightGo(content) []Token`: parse → run the embedded `highlights.scm`
    query against the root node → collect captures → map capture name to a
    canonical token type → resolve overlaps → emit non-overlapping `Token`s.
  - If init or parse fails for any reason, fall back to plain text (empty token
    list) — highlighting must never crash the core or block file viewing.
  - A size cap (`maxHighlightBytes`, 1 MiB) skips highlighting for very large
    files (return empty tokens → plain text), bounding per-call work.
- `queries/go/highlights.scm` — vendored Go highlight query, `go:embed`-ed.
- `mapping.go` — capture-name → canonical-type table and the overlap resolver.
- `offsets.go` — byte-offset → 1-based (line, column) conversion that is correct
  for multi-byte UTF-8 (column counted in the same unit the rest of the IPC uses;
  consistent with how `openFile`/navigation already report positions).

### Highlight capture resolution

`highlights.scm` produces overlapping captures (e.g. a node captured as both
`@variable` and, more specifically, `@function`). The highlighter resolves to
non-overlapping spans using the standard tree-sitter convention: for any byte,
the most specific / latest-in-query-order capture wins. Implementation: collect
all captures with (startByte, endByte, captureName), then walk a position cursor
emitting spans from the innermost enclosing capture. Tokens are emitted in
ascending start order, non-overlapping, each converted to line/column.

### Token type vocabulary (core ⇄ UI contract)

Canonical `type` strings emitted by the core and understood by the UI:

`keyword` · `string` · `comment` · `number` · `boolean` · `function` · `type` ·
`constant` · `variable` · `property` · `operator` · `punctuation` · `attribute` ·
`namespace`

Tree-sitter capture names are collapsed into this set (examples):
`function.method`, `function.builtin` → `function`; `type.builtin` → `type`;
`constant.builtin` → `boolean`/`constant`; `punctuation.bracket`,
`punctuation.delimiter` → `punctuation`; `string.escape` → `string`. Capture
names with no mapping emit **no token** (default text color). The mapping table
lives in `mapping.go` and is unit-tested.

### IPC

Unchanged. `Token{startLine, startColumn, endLine, endColumn, type}` and
`OpenFileResult` keep their shape; only the richness of `type` values changes.
Swift `SyntaxToken`/`OpenFileResult` need no schema change.

### macOS UI rendering (`apps/macos/Sources/ArchSightApp/CodeTextView.swift`)

- Build an `NSAttributedString` from `content` + `tokens`: base attributes are
  the existing monospaced font; each token sets `.foregroundColor` over its
  range. Apply by replacing the text view's `textStorage` contents. Read-only
  flags are unchanged (`isEditable = false`, `isSelectable = true`,
  `isRichText = false`) — setting attributes programmatically does not require
  rich-text editing, so no editing affordance is introduced.
- Token (line, column) → UTF-16 range using a helper symmetric to the existing
  `TextPosition.lineColumn(forUTF16Offset:in:)`, so click-offset mapping and
  color ranges share one source of truth.
- Color table maps each canonical token type to a dynamic `NSColor` (system
  semantic colors) so light/dark mode is automatic. Initial palette (tunable):
  - `keyword` → `systemPink`, `string` → `systemRed`, `comment` →
    `secondaryLabelColor`, `number`/`boolean`/`constant` → `systemOrange`,
    `function` → `systemBlue`, `type` → `systemPurple`, `property`/`variable` →
    `labelColor`, `operator`/`punctuation` → `secondaryLabelColor`,
    `attribute`/`namespace` → `systemTeal`.
- `CodeTextView` gains a `tokens: [SyntaxToken]` input (threaded from the open
  file tab). When `tokens` is empty, render plain text exactly as today.
- Read-only invariants preserved: no editing affordances, no autocomplete, no
  formatting; Cmd+Click definition / context-menu references unchanged.

### Performance & memory

- Lazy init keeps `archsight-core` startup and pre-open idle RSS unchanged; the
  perf gate measures idle RSS before any `openFile`, so the ≤50 MB budget is
  unaffected. Add a post-open measurement as a new evidence point.
- wazero is in-process — **no new child process**, so the "no child processes at
  idle" and "no orphan after SIGTERM" assertions still hold.
- Per-file highlight results are cached in memory keyed by (path, content
  identity) and invalidated on reopen/disk change, matching Phase 4's stated
  caching behavior. This also reduces instance churn (a cache hit skips
  `sitter.New` entirely).
- Files above `maxHighlightBytes` (1 MiB) skip highlighting and render as plain
  text, bounding per-call parse cost and Wasm memory.

## Components and Interfaces

| Unit | Responsibility | Depends on |
| --- | --- | --- |
| `syntax.Highlight` | Route by language; stable public API | `treesitter`, keyword fallback |
| `syntax.treesitter` | Lazy Wasm engine, parse+query Go, fallback-on-error | `malivvan/tree-sitter`, embedded `.scm` |
| `syntax.mapping` | capture→canonical type, overlap resolution | none |
| `syntax.offsets` | byte→(line,col) UTF-8 safe | none |
| `CodeTextView` | Render tokens as colors, read-only | `ArchSightKit.SyntaxToken` |
| color table | canonical type→dynamic NSColor | AppKit |

## Test Plan

### Go unit tests (`core/internal/syntax`)

- Go source with keywords, strings, line+block comments, numbers, a function
  decl, and a type decl → assert each expected token type appears at the correct
  1-based line/column span.
- Multi-byte UTF-8 content → byte→(line,col) conversion stays correct.
- Capture mapping table: representative capture names collapse to the right
  canonical types; unmapped names emit no token.
- Overlap resolution: nested captures yield non-overlapping, innermost-wins spans.
- Non-Go languages (swift/typescript) still return keyword tokens; unknown
  extensions return plain text.
- Lazy init: no Wasm instance is created until the first Go highlight; a parse
  failure degrades to empty tokens without panicking.
- **Reuse/leak regression:** highlighting a ~4 KB Go file 400 times in a row
  succeeds (guards against the ~270-parse Wasm trap that single-instance reuse
  exhibits).
- A file larger than `maxHighlightBytes` returns plain text (empty tokens).

### Swift tests (`apps/macos`)

- token list → `NSAttributedString` applies expected foreground color over the
  expected UTF-16 ranges.
- (line, column) → UTF-16 offset round-trips against the existing position
  helper, including multi-line content.
- Empty token list renders identical attributes to the plain-text path.

### Verification / perf

- `scripts/verify.sh` stays green (Go tests + Swift tests + build).
- `scripts/perf-gate.sh`: startup latency, idle RSS ≤ 50 MB, 0 child processes,
  socket cleanup, no orphan after SIGTERM — all unchanged. Capture post-`openFile`
  (Go file) RSS as a new, documented evidence point.
- Manual: open a `.go` file in the app and confirm visible, appearance-aware
  coloring; confirm Cmd+Click definition still lands on the right symbol.

## Docs to update

- `third_party/README.md`: mark Tree-sitter runtime + Go grammar + highlight
  query as vendored; record versions (tree-sitter v0.24.7, grammar revision) and
  licenses (tree-sitter MIT, tree-sitter-go grammar + query license).
- `core/README.md` and the work plan's Phase 4 implementation status: real
  Tree-sitter for Go, keyword fallback for other languages.
- `docs/performance.md`: note the post-open memory evidence point.

## Risks and Mitigations

- **Pre-release dependency churn** — pin an exact version in `go.mod`; the
  `syntax` package isolates the binding behind `Highlight`, so swapping bindings
  later is local.
- **Binary +1.5 MB from unused bundled grammars** — accepted now; revisit Wasm
  slimming (needs a C/Wasm toolchain) once the language set is locked.
- **Wasm memory leak / trap on instance reuse** (measured: trap after ~270
  parses) — mitigated by a fresh instance per highlight call; covered by a
  regression test that highlights well past that count. Revisit if a future
  binding release adds `Close`/free APIs (would let us reuse one instance for
  ~1 ms/parse).
- **Large-file highlight cost** — in-memory cache plus the `maxHighlightBytes`
  cap that degrades to plain text.
- **Query/grammar version drift** — vendor a `highlights.scm` matching the
  bundled grammar revision; record both in `third_party/README.md`.

## Out-of-scope follow-ups (noted, not built here)

- Swift / TypeScript / Markdown Tree-sitter highlighting (needs a Wasm rebuild
  to add those grammars, plus their highlight queries).
- Wasm slimming to the active language set.
- User-configurable color themes.
