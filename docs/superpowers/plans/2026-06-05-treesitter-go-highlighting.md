# Tree-sitter Go Syntax Highlighting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ArchSight's naive Go keyword highlighter with real Tree-sitter parsing (via the cgo-free wazero binding) and render the resulting tokens as colors in the read-only macOS code viewer.

**Architecture:** The Go core parses `.go` files with `github.com/malivvan/tree-sitter` (wazero Wasm runtime, no CGo), runs a vendored `highlights.scm` query, and emits the existing flat `Token` schema with a richer `type` vocabulary. A **fresh Tree-sitter instance is created per highlight call** because the pinned pre-release binding has no free/Close APIs and a reused instance traps after ~270 parses. The macOS client threads the tokens into `CodeTextView`, which applies system-semantic (light/dark-aware) foreground colors. Only Go is converted in this slice; Swift/TypeScript/Markdown keep the existing keyword adapter.

**Tech Stack:** Go 1.25, `github.com/malivvan/tree-sitter` (pinned pseudo-version), `wazero`, SwiftUI/AppKit (NSTextView), Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-06-05-treesitter-go-highlighting-design.md`

---

## File Structure

Core (`core/internal/syntax/`):
- `syntax.go` — *modify*: route `go` to the Tree-sitter highlighter; keep keyword fallback for other languages. Public API (`Highlight`, `DetectLanguage`, `Token`, `Result`) unchanged.
- `offsets.go` — *create*: UTF-8 byte offset → 1-based (line, UTF-16 column) index.
- `mapping.go` — *create*: capture-name → canonical token type, and overlap-resolving token emission.
- `treesitter.go` — *create*: per-call Tree-sitter engine that parses Go and runs the highlight query.
- `queries/go/highlights.scm` — *create (vendored)*: Go highlight query.
- `offsets_test.go`, `mapping_test.go`, `treesitter_test.go` — *create*: unit tests.

macOS (`apps/macos/`):
- `Sources/ArchSightKit/TextPosition.swift` — *modify*: add inverse `utf16Offset(forLine:column:in:)`.
- `Sources/ArchSightKit/SyntaxHighlighting.swift` — *create*: pure token → UTF-16 `HighlightSpan` mapping.
- `Sources/ArchSightKit/WorkspaceViewState.swift` — *modify*: `FileTab.tokens`; `openFile` carries tokens.
- `Sources/ArchSightKit/WorkspaceController.swift` — *modify*: `loadFile` threads `file.tokens` into the `FileTab`.
- `Sources/ArchSightApp/CodeTextView.swift` — *modify*: accept `tokens`, render colored attributed text.
- `Sources/ArchSightApp/ContentView.swift` — *modify*: pass tokens to `CodeTextView` and `openFile`.
- `Tests/ArchSightKitTests/TextPositionTests.swift` — *modify*: round-trip tests.
- `Tests/ArchSightKitTests/SyntaxHighlightingTests.swift` — *create*: span mapping tests.

Docs:
- `third_party/README.md`, `core/README.md`, `docs/performance.md`, `.omx/plans/archsight-complete-work-plan.md` — *modify*.

---

## Task 1: Add dependency and vendor the Go highlight query

**Files:**
- Modify: `go.mod`, `go.sum` (via `go get`)
- Create: `core/internal/syntax/queries/go/highlights.scm`
- Modify: `third_party/README.md`

- [ ] **Step 1: Pin the binding dependency**

The only tagged release (`v0.0.1`) ships a Wasm with C/C++ only — no Go. Go support lives on an untagged `main` commit, so pin its pseudo-version.

Run:
```bash
cd /Users/carl/Dev/CMG/ArchSight
go get github.com/malivvan/tree-sitter@46b39a7
```
Expected: `go.mod` gains `github.com/malivvan/tree-sitter v0.0.2-0.20250125152656-46b39a70b658` and the transitive `github.com/andybalholm/brotli` + `github.com/tetratelabs/wazero`.

- [ ] **Step 2: Verify the pinned version**

Run:
```bash
grep malivvan go.mod
```
Expected: `github.com/malivvan/tree-sitter v0.0.2-0.20250125152656-46b39a70b658`

- [ ] **Step 3: Vendor the Go highlight query**

Create `core/internal/syntax/queries/go/highlights.scm` with the query from `tree-sitter-go` (grammar commit `7cb21a65af6cc8e5c6742b9dba42881ea1158475`). Fetch it deterministically:
```bash
mkdir -p core/internal/syntax/queries/go
curl -fsSL "https://raw.githubusercontent.com/tree-sitter/tree-sitter-go/7cb21a65af6cc8e5c6742b9dba42881ea1158475/queries/highlights.scm" \
  -o core/internal/syntax/queries/go/highlights.scm
```
Expected: a 123-line file beginning with `; Function calls` and ending with `(comment) @comment`.

- [ ] **Step 4: Verify the query content**

Run:
```bash
head -4 core/internal/syntax/queries/go/highlights.scm; echo '---'; tail -1 core/internal/syntax/queries/go/highlights.scm
```
Expected first line `; Function calls`, last line `(comment) @comment`.

- [ ] **Step 5: Record vendoring + licenses in third_party/README.md**

In `third_party/README.md`, replace the `## Tree-sitter runtime and grammars` section body (the "not yet vendored" paragraph) with:

```markdown
## Tree-sitter runtime and grammars

- **Used for**: Go syntax highlighting (`core/internal/syntax`).
- **Binding**: `github.com/malivvan/tree-sitter`, pinned to pseudo-version
  `v0.0.2-0.20250125152656-46b39a70b658` (commit `46b39a7`). It is cgo-free: it
  embeds a Wasm build of tree-sitter `v0.24.7` and runs it on `wazero`
  (`github.com/tetratelabs/wazero`), with `github.com/andybalholm/brotli` for
  Wasm decompression. The tagged `v0.0.1` release embeds only C/C++; the pinned
  commit's Wasm includes the `go` grammar (and ~20 others). Swift/TypeScript/
  Markdown are NOT in the shipped Wasm and need a Wasm rebuild to add later.
- **Highlight query**: `core/internal/syntax/queries/go/highlights.scm`, vendored
  from `tree-sitter/tree-sitter-go` commit
  `7cb21a65af6cc8e5c6742b9dba42881ea1158475` (`queries/highlights.scm`).
- **Licenses**: tree-sitter runtime — MIT (tree-sitter/tree-sitter). `wazero` —
  Apache-2.0. `brotli` (andybalholm) — MIT. tree-sitter-go grammar + query — MIT
  (tree-sitter/tree-sitter-go).
- **Packaging**: pure Go; the Wasm is embedded inside the binding via `go:embed`,
  so it ships inside `archsight-core` with no extra files. Highlighting is
  on-demand and adds no idle memory or child processes.
```

- [ ] **Step 6: Commit**

```bash
git add go.mod go.sum core/internal/syntax/queries/go/highlights.scm third_party/README.md
git commit -m "feat: [syntax] vendor tree-sitter wazero binding and Go highlight query"
```

---

## Task 2: Byte offset → line/UTF-16-column index

**Files:**
- Create: `core/internal/syntax/offsets.go`
- Test: `core/internal/syntax/offsets_test.go`

The macOS client's position contract (see `apps/macos/Sources/ArchSightKit/TextPosition.swift`) is **1-based line, 1-based column counted in UTF-16 code units**. Tree-sitter reports UTF-8 byte offsets, so the core must convert.

- [ ] **Step 1: Write the failing test**

Create `core/internal/syntax/offsets_test.go`:
```go
package syntax

import "testing"

func TestLineColumnIndexAscii(t *testing.T) {
	content := "package main\nfunc f() {}\n"
	idx := newLineColumnIndex(content)

	// byte 0 -> line 1, col 1
	if l, c := idx.at(0); l != 1 || c != 1 {
		t.Fatalf("at(0) = (%d,%d), want (1,1)", l, c)
	}
	// "func" starts at byte 13 (after "package main\n") -> line 2, col 1
	if l, c := idx.at(13); l != 2 || c != 1 {
		t.Fatalf("at(13) = (%d,%d), want (2,1)", l, c)
	}
	// byte 17 is 'f' of f() -> line 2, col 6
	if l, c := idx.at(18); l != 2 || c != 6 {
		t.Fatalf("at(18) = (%d,%d), want (2,6)", l, c)
	}
}

func TestLineColumnIndexUTF16Columns(t *testing.T) {
	// "é" is 2 UTF-8 bytes but 1 UTF-16 unit; "😀" is 4 UTF-8 bytes and 2 UTF-16 units.
	content := "a\"é\"😀x"
	idx := newLineColumnIndex(content)
	// bytes: a(0) "(1) é(2,3) "(4) 😀(5,6,7,8) x(9)
	// UTF-16 units before byte 9: a, ", é, ", 😀(2 units) = 6 -> column 7.
	if l, c := idx.at(9); l != 1 || c != 7 {
		t.Fatalf("at(9) = (%d,%d), want (1,7)", l, c)
	}
}

func TestLineColumnIndexClamps(t *testing.T) {
	idx := newLineColumnIndex("abc")
	if l, c := idx.at(-5); l != 1 || c != 1 {
		t.Fatalf("at(-5) = (%d,%d), want (1,1)", l, c)
	}
	if l, c := idx.at(999); l != 1 || c != 4 {
		t.Fatalf("at(999) = (%d,%d), want (1,4)", l, c)
	}
}
```

NOTE: the second test's expected column is **7** (a=1, `"`=2, é=3, `"`=4, 😀=cols 5–6, x at col 7). Fix the literal to `c != 7` and message `want (1,7)` before running.

- [ ] **Step 2: Run the test to verify it fails**

Run: `go test ./core/internal/syntax/ -run TestLineColumnIndex -v`
Expected: FAIL — `newLineColumnIndex` undefined.

- [ ] **Step 3: Implement offsets.go**

Create `core/internal/syntax/offsets.go`:
```go
package syntax

// lineColumnIndex converts a UTF-8 byte offset into a 1-based line and a 1-based
// column counted in UTF-16 code units, matching the position contract the macOS
// client uses (see apps/macos TextPosition).
type lineColumnIndex struct {
	content    string
	lineStarts []int // byte offset of each line start; line 1 at index 0
}

func newLineColumnIndex(content string) *lineColumnIndex {
	starts := []int{0}
	for i := 0; i < len(content); i++ {
		if content[i] == '\n' {
			starts = append(starts, i+1)
		}
	}
	return &lineColumnIndex{content: content, lineStarts: starts}
}

// at returns the 1-based (line, column) for a byte offset. Offsets are clamped
// to [0, len(content)]. Callers pass node boundary offsets, which fall on valid
// UTF-8 rune boundaries.
func (x *lineColumnIndex) at(byteOffset int) (int, int) {
	if byteOffset < 0 {
		byteOffset = 0
	}
	if byteOffset > len(x.content) {
		byteOffset = len(x.content)
	}
	lo, hi := 0, len(x.lineStarts)-1
	for lo < hi {
		mid := (lo + hi + 1) / 2
		if x.lineStarts[mid] <= byteOffset {
			lo = mid
		} else {
			hi = mid - 1
		}
	}
	line := lo + 1
	col := 1 + utf16Len(x.content[x.lineStarts[lo]:byteOffset])
	return line, col
}

// utf16Len counts the UTF-16 code units in s (surrogate pairs count as 2).
func utf16Len(s string) int {
	n := 0
	for _, r := range s {
		if r > 0xFFFF {
			n += 2
		} else {
			n++
		}
	}
	return n
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `go test ./core/internal/syntax/ -run TestLineColumnIndex -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add core/internal/syntax/offsets.go core/internal/syntax/offsets_test.go
git commit -m "feat: [syntax] add byte-offset to line/UTF-16-column index"
```

---

## Task 3: Capture mapping and overlap-resolving token emission

**Files:**
- Create: `core/internal/syntax/mapping.go`
- Test: `core/internal/syntax/mapping_test.go`

Tree-sitter captures overlap (e.g. a call's identifier is captured as both `@function` and `@variable`; `@escape` sits inside `@string`). We resolve to non-overlapping spans where the most specific (shortest) capture wins, ties broken by the lower pattern index, then coalesce same-type runs. `@variable` and `@property` are intentionally NOT emitted — they would render as the default text color, so emitting them is pure overhead.

- [ ] **Step 1: Write the failing test**

Create `core/internal/syntax/mapping_test.go`:
```go
package syntax

import "testing"

func TestCanonicalType(t *testing.T) {
	cases := map[string]string{
		"keyword":          "keyword",
		"string":           "string",
		"escape":           "string",
		"comment":          "comment",
		"number":           "number",
		"constant.builtin": "constant",
		"function":         "function",
		"function.method":  "function",
		"function.builtin": "function",
		"type":             "type",
		"operator":         "operator",
		"variable":         "", // not emitted (renders as default text color)
		"property":         "", // not emitted
		"unknownthing":     "",
	}
	for name, want := range cases {
		if got := canonicalType(name); got != want {
			t.Errorf("canonicalType(%q) = %q, want %q", name, got, want)
		}
	}
}

func TestResolveTokensPrefersShorterThenLowerPattern(t *testing.T) {
	// content: identifier "greet" (bytes 0..5) captured as both function (pattern 0)
	// and variable (pattern 2). variable maps to "" (skipped), function wins.
	content := "greet"
	idx := newLineColumnIndex(content)
	caps := []rawCapture{
		{start: 0, end: 5, pattern: 2, typ: ""},         // variable -> skipped upstream; pass typ "" to ensure it's ignored
		{start: 0, end: 5, pattern: 0, typ: "function"}, // function
	}
	tokens := resolveTokens(content, caps, idx)
	if len(tokens) != 1 {
		t.Fatalf("want 1 token, got %d: %+v", len(tokens), tokens)
	}
	tok := tokens[0]
	if tok.Type != "function" || tok.StartColumn != 1 || tok.EndColumn != 6 {
		t.Fatalf("unexpected token: %+v", tok)
	}
}

func TestResolveTokensCoalescesStringWithEscape(t *testing.T) {
	// "a\nb" as a Go string literal: outer string (bytes 0..6) with an escape
	// (bytes 2..4) inside. Both map to "string" -> one contiguous token.
	content := `"a\nb"`
	idx := newLineColumnIndex(content)
	caps := []rawCapture{
		{start: 0, end: 6, pattern: 5, typ: "string"},
		{start: 2, end: 4, pattern: 6, typ: "string"},
	}
	tokens := resolveTokens(content, caps, idx)
	if len(tokens) != 1 || tokens[0].Type != "string" || tokens[0].StartColumn != 1 || tokens[0].EndColumn != 7 {
		t.Fatalf("want one string token spanning the literal, got %+v", tokens)
	}
}

func TestResolveTokensSkipsEmptyAndOutOfRange(t *testing.T) {
	content := "abc"
	idx := newLineColumnIndex(content)
	caps := []rawCapture{
		{start: 0, end: 3, pattern: 0, typ: ""},   // skipped: empty type
		{start: 1, end: 99, pattern: 0, typ: "x"}, // skipped: out of range
	}
	if tokens := resolveTokens(content, caps, idx); len(tokens) != 0 {
		t.Fatalf("want 0 tokens, got %+v", tokens)
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `go test ./core/internal/syntax/ -run 'TestCanonicalType|TestResolveTokens' -v`
Expected: FAIL — `canonicalType`, `rawCapture`, `resolveTokens` undefined.

- [ ] **Step 3: Implement mapping.go**

Create `core/internal/syntax/mapping.go`:
```go
package syntax

import "sort"

// canonicalType maps a tree-sitter highlight capture name to ArchSight's stable
// token-type vocabulary. It returns "" for captures we do not render (including
// @variable/@property, which would only repaint the default text color).
func canonicalType(capture string) string {
	switch capture {
	case "keyword":
		return "keyword"
	case "string", "escape":
		return "string"
	case "comment":
		return "comment"
	case "number":
		return "number"
	case "constant", "constant.builtin":
		return "constant"
	case "function", "function.builtin", "function.method":
		return "function"
	case "type", "type.builtin":
		return "type"
	case "operator":
		return "operator"
	default:
		return ""
	}
}

// rawCapture is a single highlight capture in UTF-8 byte coordinates.
type rawCapture struct {
	start, end int    // byte offsets [start, end)
	pattern    int    // query pattern index; lower = higher priority
	typ        string // canonical token type ("" = ignore)
}

// resolveTokens paints non-overlapping highlight spans (most specific/shortest
// capture wins, ties broken by lower pattern index, then earlier start) and
// coalesces consecutive same-type bytes into Tokens with 1-based line/column.
func resolveTokens(content string, caps []rawCapture, idx *lineColumnIndex) []Token {
	n := len(content)
	owner := make([]int16, n)
	for i := range owner {
		owner[i] = -1
	}
	var types []string
	typeID := map[string]int16{}
	idFor := func(t string) int16 {
		if id, ok := typeID[t]; ok {
			return id
		}
		id := int16(len(types))
		types = append(types, t)
		typeID[t] = id
		return id
	}

	sorted := make([]rawCapture, 0, len(caps))
	for _, c := range caps {
		if c.typ == "" || c.start < 0 || c.end > n || c.start >= c.end {
			continue
		}
		sorted = append(sorted, c)
	}
	sort.SliceStable(sorted, func(a, b int) bool {
		la, lb := sorted[a].end-sorted[a].start, sorted[b].end-sorted[b].start
		if la != lb {
			return la < lb
		}
		if sorted[a].pattern != sorted[b].pattern {
			return sorted[a].pattern < sorted[b].pattern
		}
		return sorted[a].start < sorted[b].start
	})
	for _, c := range sorted {
		id := idFor(c.typ)
		for i := c.start; i < c.end; i++ {
			if owner[i] == -1 {
				owner[i] = id
			}
		}
	}

	var tokens []Token
	i := 0
	for i < n {
		if owner[i] == -1 {
			i++
			continue
		}
		j := i + 1
		for j < n && owner[j] == owner[i] {
			j++
		}
		sl, sc := idx.at(i)
		el, ec := idx.at(j)
		tokens = append(tokens, Token{
			StartLine:   sl,
			StartColumn: sc,
			EndLine:     el,
			EndColumn:   ec,
			Type:        types[owner[i]],
		})
		i = j
	}
	if tokens == nil {
		return []Token{}
	}
	return tokens
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `go test ./core/internal/syntax/ -run 'TestCanonicalType|TestResolveTokens' -v`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add core/internal/syntax/mapping.go core/internal/syntax/mapping_test.go
git commit -m "feat: [syntax] add capture mapping and overlap-resolving token emission"
```

---

## Task 4: Tree-sitter Go highlighter engine

**Files:**
- Create: `core/internal/syntax/treesitter.go`
- Test: `core/internal/syntax/treesitter_test.go`

Per-call instance (no reuse): the pinned binding exposes no free/Close for trees/cursors/modules, so a reused instance leaks Wasm memory and traps after ~270 parses (measured). A fresh instance is reclaimed after each call; only the first call pays the Wasm compile (~90 ms), the rest ~6–13 ms.

- [ ] **Step 1: Write the failing test**

Create `core/internal/syntax/treesitter_test.go`:
```go
package syntax

import (
	"strings"
	"testing"
)

const goSample = `package main

import "fmt"

// greet returns a greeting.
func greet(name string) string {
	return "hello, " + name
}

func main() {
	fmt.Println(greet("world"))
}
`

func tokensByType(tokens []Token) map[string]int {
	m := map[string]int{}
	for _, t := range tokens {
		m[t.Type]++
	}
	return m
}

func TestHighlightGoProducesRichTokens(t *testing.T) {
	tokens := highlightGo(goSample)
	if len(tokens) == 0 {
		t.Fatal("expected tokens for Go source")
	}
	counts := tokensByType(tokens)
	for _, typ := range []string{"keyword", "string", "comment", "function"} {
		if counts[typ] == 0 {
			t.Errorf("expected at least one %q token; got counts %+v", typ, counts)
		}
	}
	// Skipped capture types must never be emitted.
	for _, tok := range tokens {
		if tok.Type == "" || tok.Type == "variable" || tok.Type == "property" {
			t.Errorf("unexpected token type %q emitted", tok.Type)
		}
	}
}

func TestHighlightGoCommentPosition(t *testing.T) {
	// The comment is on line 5, starting at column 1.
	tokens := highlightGo(goSample)
	var found bool
	for _, tok := range tokens {
		if tok.Type == "comment" {
			found = true
			if tok.StartLine != 5 || tok.StartColumn != 1 {
				t.Fatalf("comment token at (%d,%d), want (5,1)", tok.StartLine, tok.StartColumn)
			}
		}
	}
	if !found {
		t.Fatal("no comment token found")
	}
}

func TestHighlightGoEmptyAndOversize(t *testing.T) {
	if got := highlightGo(""); len(got) != 0 {
		t.Fatalf("empty content should yield no tokens, got %d", len(got))
	}
	huge := "package main\n" + strings.Repeat("var x = 1\n", maxHighlightBytes/10)
	if len(huge) <= maxHighlightBytes {
		t.Fatalf("test fixture not large enough: %d", len(huge))
	}
	if got := highlightGo(huge); len(got) != 0 {
		t.Fatalf("oversize content should yield no tokens, got %d", len(got))
	}
}

func TestHighlightGoReuseDoesNotTrap(t *testing.T) {
	// Regression: a reused single instance traps (wasm unreachable) after ~270
	// parses. Per-call instances must survive well past that.
	src := "package main\n" + strings.Repeat("func f(x int) int { return x } // c\n", 80)
	for i := 0; i < 400; i++ {
		if len(highlightGo(src)) == 0 {
			t.Fatalf("highlight returned no tokens at iteration %d", i)
		}
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `go test ./core/internal/syntax/ -run TestHighlightGo -v`
Expected: FAIL — `highlightGo`, `maxHighlightBytes` undefined.

- [ ] **Step 3: Implement treesitter.go**

Create `core/internal/syntax/treesitter.go`:
```go
package syntax

import (
	_ "embed"
	"fmt"

	sitter "github.com/malivvan/tree-sitter"
)

//go:embed queries/go/highlights.scm
var goHighlightQuery string

// maxHighlightBytes caps the file size we highlight; larger files render as
// plain text. This bounds per-call parse cost and Wasm memory.
const maxHighlightBytes = 1 << 20 // 1 MiB

// highlightGo returns Tree-sitter highlight tokens for Go source. Any failure
// (init, parse, query, or panic) degrades to an empty slice so highlighting
// never blocks file viewing or crashes the core.
func highlightGo(content string) []Token {
	if len(content) == 0 || len(content) > maxHighlightBytes {
		return []Token{}
	}
	tokens, err := tryHighlightGo(content)
	if err != nil || tokens == nil {
		return []Token{}
	}
	return tokens
}

// tryHighlightGo builds a fresh Tree-sitter instance, parses, runs the highlight
// query, and resolves tokens. A fresh instance per call is required: the pinned
// binding has no free/Close for trees/cursors/modules, so a reused instance
// leaks Wasm memory and traps after a few hundred parses. The compiled Wasm
// module is cached process-globally by the binding, so only the first call pays
// the compile cost.
func tryHighlightGo(content string) (_ []Token, err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("tree-sitter highlight panicked: %v", r)
		}
	}()

	ts, err := sitter.New(nil, nil)
	if err != nil {
		return nil, err
	}
	lang, err := ts.Language("go")
	if err != nil {
		return nil, err
	}
	query, err := ts.NewQuery(goHighlightQuery, lang)
	if err != nil {
		return nil, err
	}
	parser, err := ts.NewParser()
	if err != nil {
		return nil, err
	}
	defer parser.Close()
	if err := parser.SetLanguage(lang); err != nil {
		return nil, err
	}
	tree, err := parser.ParseString(content)
	if err != nil {
		return nil, err
	}
	root, err := tree.RootNode()
	if err != nil {
		return nil, err
	}
	cursor, err := ts.NewQueryCursor()
	if err != nil {
		return nil, err
	}
	if err := cursor.Exec(query, root); err != nil {
		return nil, err
	}

	var caps []rawCapture
	for {
		match, ok, err := cursor.NextMatch()
		if err != nil {
			return nil, err
		}
		if !ok {
			break
		}
		for _, c := range match.Captures {
			name, err := query.CaptureNameForID(c.ID)
			if err != nil {
				return nil, err
			}
			typ := canonicalType(name)
			if typ == "" {
				continue
			}
			sb, err := c.Node.StartByte()
			if err != nil {
				return nil, err
			}
			eb, err := c.Node.EndByte()
			if err != nil {
				return nil, err
			}
			caps = append(caps, rawCapture{
				start:   int(sb),
				end:     int(eb),
				pattern: int(match.PatternIndex),
				typ:     typ,
			})
		}
	}
	return resolveTokens(content, caps, newLineColumnIndex(content)), nil
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `go test ./core/internal/syntax/ -run TestHighlightGo -v`
Expected: PASS (4 tests). The reuse-regression test runs 400 highlights; allow a few seconds.

- [ ] **Step 5: Commit**

```bash
git add core/internal/syntax/treesitter.go core/internal/syntax/treesitter_test.go
git commit -m "feat: [syntax] add per-call tree-sitter Go highlighter"
```

---

## Task 5: Route Go through Tree-sitter in the public API

**Files:**
- Modify: `core/internal/syntax/syntax.go`
- Test: `core/internal/syntax/syntax_test.go` (create)

- [ ] **Step 1: Write the failing test**

Create `core/internal/syntax/syntax_test.go`:
```go
package syntax

import "testing"

func TestHighlightRoutesGoToTreeSitter(t *testing.T) {
	res := Highlight("cmd/main.go", goSample)
	if res.Language != "go" {
		t.Fatalf("language = %q, want go", res.Language)
	}
	if tokensByType(res.Tokens)["function"] == 0 {
		t.Fatalf("expected tree-sitter function tokens, got %+v", res.Tokens)
	}
}

func TestHighlightKeepsKeywordFallbackForSwift(t *testing.T) {
	res := Highlight("App.swift", "import SwiftUI\nclass A {}\n")
	if res.Language != "swift" {
		t.Fatalf("language = %q, want swift", res.Language)
	}
	if len(res.Tokens) == 0 {
		t.Fatal("expected keyword tokens for swift")
	}
	for _, tok := range res.Tokens {
		if tok.Type != "keyword" {
			t.Fatalf("swift fallback should emit only keyword tokens, got %q", tok.Type)
		}
	}
}

func TestHighlightPlainTextForUnknown(t *testing.T) {
	res := Highlight("notes.txt", "hello world\n")
	if res.Language != "" || len(res.Tokens) != 0 {
		t.Fatalf("unknown extension should be plain text, got %+v", res)
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `go test ./core/internal/syntax/ -run TestHighlightRoutes -v`
Expected: FAIL — `Highlight` still returns keyword tokens for Go (no `function` type).

- [ ] **Step 3: Modify Highlight in syntax.go**

In `core/internal/syntax/syntax.go`, replace the `Highlight` function body:
```go
func Highlight(path, content string) Result {
	language := DetectLanguage(path)
	if language == "" {
		return Result{Tokens: []Token{}}
	}
	if language == "go" {
		return Result{Language: language, Tokens: highlightGo(content)}
	}
	return Result{
		Language: language,
		Tokens:   keywordTokens(language, content),
	}
}
```
Leave `DetectLanguage`, `keywordTokens`, `keywordsFor`, `isIdentStart`, `isIdentPart` unchanged (still used by the Swift/TypeScript/Markdown fallback).

- [ ] **Step 4: Run the syntax + full core tests**

Run: `go test ./core/internal/syntax/ -v`
Expected: PASS (all syntax tests).

Run: `go test ./core/...`
Expected: PASS — including `core/internal/ipc` `TestServerOpenFileReturnsReadOnlyContentAndSyntaxTokens` (Go file still yields tokens) and the unsupported-language plain-text test.

- [ ] **Step 5: Commit**

```bash
git add core/internal/syntax/syntax.go core/internal/syntax/syntax_test.go
git commit -m "feat: [syntax] route Go highlighting through tree-sitter"
```

---

## Task 6: Swift inverse position helper (line/column → UTF-16 offset)

**Files:**
- Modify: `apps/macos/Sources/ArchSightKit/TextPosition.swift`
- Test: `apps/macos/Tests/ArchSightKitTests/TextPositionTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `apps/macos/Tests/ArchSightKitTests/TextPositionTests.swift` (inside the existing `TextPositionTests` class):
```swift
    func testUTF16OffsetRoundTripsWithLineColumn() {
        let text = "package main\nfunc f() {}\n"
        for offset in 0...text.utf16.count {
            let pos = TextPosition.lineColumn(forUTF16Offset: offset, in: text)
            let back = TextPosition.utf16Offset(forLine: pos.line, column: pos.column, in: text)
            XCTAssertEqual(back, offset, "round trip failed at offset \(offset)")
        }
    }

    func testUTF16OffsetForLineColumnWithMultibyte() {
        let text = "let s = \"é😀\"\nx"
        // line 2, column 1 is the byte right after the newline -> 'x'
        let offset = TextPosition.utf16Offset(forLine: 2, column: 1, in: text)
        let units = Array(text.utf16)
        XCTAssertEqual(units[offset], UInt16(UnicodeScalar("x").value))
    }

    func testUTF16OffsetColumnBeyondLineClampsToLineEnd() {
        let text = "ab\ncd\n"
        // column 99 on line 1 should clamp at the newline (offset 2)
        XCTAssertEqual(TextPosition.utf16Offset(forLine: 1, column: 99, in: text), 2)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/macos && swift test --filter TextPositionTests`
Expected: FAIL — `utf16Offset(forLine:column:in:)` not found.

- [ ] **Step 3: Implement the inverse helper**

In `apps/macos/Sources/ArchSightKit/TextPosition.swift`, add inside the `TextPosition` enum (after the existing `lineColumn` method):
```swift
    /// Inverse of `lineColumn`: converts a 1-based line and 1-based UTF-16 column
    /// into a UTF-16 offset. Lines and columns beyond the text clamp to the
    /// nearest valid offset (line end for an over-long column).
    public static func utf16Offset(forLine line: Int, column: Int, in text: String) -> Int {
        let units = Array(text.utf16)
        var currentLine = 1
        var index = 0
        while currentLine < line && index < units.count {
            if units[index] == 0x0A {
                currentLine += 1
            }
            index += 1
        }
        var col = 1
        while col < column && index < units.count && units[index] != 0x0A {
            index += 1
            col += 1
        }
        return index
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/macos && swift test --filter TextPositionTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Sources/ArchSightKit/TextPosition.swift apps/macos/Tests/ArchSightKitTests/TextPositionTests.swift
git commit -m "feat: [macos] add line/column to UTF-16 offset helper"
```

---

## Task 7: Token → UTF-16 highlight spans (pure, testable)

**Files:**
- Create: `apps/macos/Sources/ArchSightKit/SyntaxHighlighting.swift`
- Test: `apps/macos/Tests/ArchSightKitTests/SyntaxHighlightingTests.swift`

- [ ] **Step 1: Write the failing test**

Create `apps/macos/Tests/ArchSightKitTests/SyntaxHighlightingTests.swift`:
```swift
import XCTest
@testable import ArchSightKit

final class SyntaxHighlightingTests: XCTestCase {
    private func token(_ sl: Int, _ sc: Int, _ el: Int, _ ec: Int, _ type: String) -> SyntaxToken {
        // Decode through JSON to build a SyntaxToken (its memberwise init is synthesized).
        let json = """
        {"startLine":\(sl),"startColumn":\(sc),"endLine":\(el),"endColumn":\(ec),"type":"\(type)"}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(SyntaxToken.self, from: json)
    }

    func testSpansMapTokenToUTF16Range() {
        let content = "func f() {}\n"
        // "func" is line 1, columns 1..5 (end exclusive)
        let tokens = [token(1, 1, 1, 5, "keyword")]
        let spans = SyntaxHighlighting.spans(for: tokens, in: content)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].type, "keyword")
        XCTAssertEqual(spans[0].range, NSRange(location: 0, length: 4))
    }

    func testSpansDropInvalidRanges() {
        let content = "abc"
        let tokens = [
            token(1, 3, 1, 2, "keyword"),  // end before start
            token(9, 1, 9, 5, "string"),   // beyond content
        ]
        XCTAssertTrue(SyntaxHighlighting.spans(for: tokens, in: content).isEmpty)
    }

    func testSpansHandleMultibyteContent() {
        let content = "x = \"é\" // c\n"
        // The comment "// c" — compute its columns: x(1) space(2) =(3) space(4)
        // "(5) é(6) "(7) space(8) /(9)/(10) space(11) c(12) -> comment cols 9..13
        let tokens = [token(1, 9, 1, 13, "comment")]
        let spans = SyntaxHighlighting.spans(for: tokens, in: content)
        XCTAssertEqual(spans.count, 1)
        let ns = content as NSString
        XCTAssertEqual(ns.substring(with: spans[0].range), "// c")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/macos && swift test --filter SyntaxHighlightingTests`
Expected: FAIL — `SyntaxHighlighting` / `HighlightSpan` not found.

- [ ] **Step 3: Implement SyntaxHighlighting.swift**

Create `apps/macos/Sources/ArchSightKit/SyntaxHighlighting.swift`:
```swift
import Foundation

/// A UTF-16 range over file content paired with its canonical token type, ready
/// for the read-only code viewer to colorize. AppKit-free so it is unit-testable.
public struct HighlightSpan: Equatable, Sendable {
    public let range: NSRange
    public let type: String

    public init(range: NSRange, type: String) {
        self.range = range
        self.type = type
    }
}

public enum SyntaxHighlighting {
    /// Converts syntax tokens (1-based line / UTF-16 column) into UTF-16 ranges.
    /// Tokens whose range is empty, inverted, or out of bounds are dropped.
    public static func spans(for tokens: [SyntaxToken], in content: String) -> [HighlightSpan] {
        let unitCount = content.utf16.count
        var spans: [HighlightSpan] = []
        spans.reserveCapacity(tokens.count)
        for token in tokens {
            let start = TextPosition.utf16Offset(forLine: token.startLine, column: token.startColumn, in: content)
            let end = TextPosition.utf16Offset(forLine: token.endLine, column: token.endColumn, in: content)
            guard start >= 0, end > start, end <= unitCount else { continue }
            spans.append(HighlightSpan(range: NSRange(location: start, length: end - start), type: token.type))
        }
        return spans
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/macos && swift test --filter SyntaxHighlightingTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Sources/ArchSightKit/SyntaxHighlighting.swift apps/macos/Tests/ArchSightKitTests/SyntaxHighlightingTests.swift
git commit -m "feat: [macos] map syntax tokens to UTF-16 highlight spans"
```

---

## Task 8: Thread tokens through FileTab, openFile, and loadFile

**Files:**
- Modify: `apps/macos/Sources/ArchSightKit/WorkspaceViewState.swift`
- Modify: `apps/macos/Sources/ArchSightKit/WorkspaceController.swift`
- Test: `apps/macos/Tests/ArchSightKitTests/AppStateTests.swift` (add one test)

- [ ] **Step 1: Write the failing test**

Append to `apps/macos/Tests/ArchSightKitTests/AppStateTests.swift` (inside the existing test class):
```swift
    func testOpenFileCarriesTokens() {
        let json = """
        {"startLine":1,"startColumn":1,"endLine":1,"endColumn":5,"type":"keyword"}
        """.data(using: .utf8)!
        let token = try! JSONDecoder().decode(SyntaxToken.self, from: json)
        var state = WorkspaceViewState()
        state.openFile(rootID: "r", path: "main.go", content: "func x() {}", tokens: [token])
        XCTAssertEqual(state.openTabs.first?.tokens, [token])
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/macos && swift test --filter AppStateTests`
Expected: FAIL — `openFile` has no `tokens:` parameter; `FileTab` has no `tokens`.

- [ ] **Step 3: Add tokens to FileTab and openFile**

In `apps/macos/Sources/ArchSightKit/WorkspaceViewState.swift`, update `FileTab`:
```swift
public struct FileTab: Equatable, Identifiable, Sendable {
    public let id: String
    public let rootID: String
    public let path: String
    public let content: String
    public let tokens: [SyntaxToken]
    public let isReadOnly: Bool

    public init(rootID: String, path: String, content: String, tokens: [SyntaxToken] = [], isReadOnly: Bool = true) {
        self.id = rootID + ":" + path
        self.rootID = rootID
        self.path = path
        self.content = content
        self.tokens = tokens
        self.isReadOnly = isReadOnly
    }
}
```
And update `openFile`:
```swift
    public mutating func openFile(rootID: String, path: String, content: String, tokens: [SyntaxToken] = []) {
        let tab = FileTab(rootID: rootID, path: path, content: content, tokens: tokens)
        if let existing = openTabs.firstIndex(where: { $0.id == tab.id }) {
            openTabs[existing] = tab
        } else {
            openTabs.append(tab)
        }
        selectedTabID = tab.id
    }
```

- [ ] **Step 4: Thread tokens through loadFile**

In `apps/macos/Sources/ArchSightKit/WorkspaceController.swift`, update `loadFile`:
```swift
    public func loadFile(workspaceId: String, rootId: String, path: String) throws -> FileTab {
        let file = try client.openFile(workspaceId: workspaceId, rootId: rootId, path: path)
        return FileTab(rootID: file.rootId, path: file.path, content: file.content, tokens: file.tokens)
    }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd apps/macos && swift test --filter AppStateTests`
Expected: PASS. (Existing `openFile`/`FileTab` calls compile unchanged thanks to the defaulted `tokens` parameter.)

- [ ] **Step 6: Commit**

```bash
git add apps/macos/Sources/ArchSightKit/WorkspaceViewState.swift apps/macos/Sources/ArchSightKit/WorkspaceController.swift apps/macos/Tests/ArchSightKitTests/AppStateTests.swift
git commit -m "feat: [macos] carry syntax tokens on file tabs"
```

---

## Task 9: Render colored tokens in the read-only code viewer

**Files:**
- Modify: `apps/macos/Sources/ArchSightApp/CodeTextView.swift`
- Modify: `apps/macos/Sources/ArchSightApp/ContentView.swift`

This task is UI wiring verified by build + manual run (NSTextView attribute rendering is not unit-tested; the span computation is already covered in Task 7). Keep all read-only flags intact.

- [ ] **Step 1: Add tokens input and color rendering to CodeTextView**

In `apps/macos/Sources/ArchSightApp/CodeTextView.swift`:

(a) Add the `tokens` stored property to the `CodeTextView` struct, right after `let content: String`:
```swift
    let content: String
    var tokens: [SyntaxToken] = []
```

(b) Replace the content-update block in `updateNSView` (the `if textView.string != content { ... }` block) with:
```swift
        if textView.string != content {
            let attributed = NSMutableAttributedString(
                string: content,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.labelColor,
                ]
            )
            for span in SyntaxHighlighting.spans(for: tokens, in: content) where NSMaxRange(span.range) <= attributed.length {
                attributed.addAttribute(.foregroundColor, value: Self.color(for: span.type), range: span.range)
            }
            textView.textStorage?.setAttributedString(attributed)
            textView.lastScrolledLine = nil
        }
```

(c) Add the color table as a static method on `CodeTextView` (after `makeCoordinator()`):
```swift
    /// Maps a canonical token type to a dynamic system color so highlighting
    /// follows light/dark appearance automatically.
    static func color(for type: String) -> NSColor {
        switch type {
        case "keyword": return .systemPink
        case "string": return .systemRed
        case "comment": return .secondaryLabelColor
        case "number", "constant": return .systemOrange
        case "function": return .systemBlue
        case "type": return .systemPurple
        case "operator": return .secondaryLabelColor
        default: return .labelColor
        }
    }
```

The text view keeps `isEditable = false`, `isSelectable = true`, `isRichText = false`; setting attributes programmatically introduces no editing affordance.

- [ ] **Step 2: Pass tokens from ContentView**

In `apps/macos/Sources/ArchSightApp/ContentView.swift`, find the `CodeTextView(` construction (around line 249) and add the `tokens` argument:
```swift
        CodeTextView(
            content: tab.content,
            tokens: tab.tokens,
            scrollToLine: ...   // leave the existing remaining arguments unchanged
```
(Keep `scrollToLine`, `onDefinition`, `onReferences` exactly as they are.)

- [ ] **Step 3: Pass tokens when opening a loaded tab**

In `apps/macos/Sources/ArchSightApp/ContentView.swift`, find the `loadFile` success path (around line 448):
```swift
                state.openFile(rootID: tab.rootID, path: tab.path, content: tab.content)
```
Replace with:
```swift
                state.openFile(rootID: tab.rootID, path: tab.path, content: tab.content, tokens: tab.tokens)
```

- [ ] **Step 4: Build and run the macOS package tests**

Run: `cd apps/macos && swift build`
Expected: `Build complete!`

Run: `cd apps/macos && swift test`
Expected: all tests pass (no regressions).

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Sources/ArchSightApp/CodeTextView.swift apps/macos/Sources/ArchSightApp/ContentView.swift
git commit -m "feat: [macos] colorize read-only code viewer with syntax tokens"
```

---

## Task 10: Docs, full verification, and performance evidence

**Files:**
- Modify: `core/README.md`, `docs/performance.md`, `.omx/plans/archsight-complete-work-plan.md`

- [ ] **Step 1: Update core/README.md syntax notes**

In `core/README.md`, find the Phase 4 / syntax description and update it to state that Go highlighting now uses real Tree-sitter (wazero binding, per-call instance, vendored `highlights.scm`), while Swift/TypeScript/Markdown keep the keyword adapter and unknown extensions degrade to plain text. (Match the file's existing heading style; keep it to a short paragraph.)

- [ ] **Step 2: Update the work plan Phase 4 status**

In `.omx/plans/archsight-complete-work-plan.md`, under "### Phase 4: Syntax Pipeline" → "Implementation status", append a bullet:
```markdown
- Go highlighting now uses real Tree-sitter via the cgo-free wazero binding
  (`github.com/malivvan/tree-sitter`, pinned) with a vendored
  `tree-sitter-go` `highlights.scm`; a fresh parser instance is built per
  highlight (the pinned binding has no tree/cursor free APIs and a reused
  instance traps after ~270 parses). Swift/TypeScript/Markdown keep the keyword
  adapter; unknown extensions stay plain text.
```

- [ ] **Step 3: Run the full verification suite**

Run: `bash scripts/verify.sh`
Expected: ends with `Verification passed.` — Go tests (incl. new `core/internal/syntax` tests), `go build`, Swift tests, and `swift build` all OK.

- [ ] **Step 4: Run the performance/reliability gate and capture evidence**

Run: `bash scripts/perf-gate.sh`
Expected: startup latency reported, idle RSS under the 50 MB budget, 0 child processes, socket removed, no orphan processes, workspace unchanged. (Idle RSS is measured before any file is opened, so the lazy Wasm load does not affect it.)

- [ ] **Step 5: Add a performance note**

In `docs/performance.md`, add a short note under the existing evidence section:
```markdown
Syntax highlighting parses on demand with a fresh Tree-sitter (wazero) instance
per opened file: the first Go file in a session pays a one-time Wasm compile
(~90 ms), subsequent files ~6–13 ms. Highlighting runs in-process (no child
process) and does not affect idle memory, which is measured before any file is
opened.
```

- [ ] **Step 6: Final commit**

```bash
git add core/README.md docs/performance.md .omx/plans/archsight-complete-work-plan.md
git commit -m "docs: [syntax] record tree-sitter Go highlighting across docs and plan"
```

---

## Verification Summary

After Task 10, all of these must hold:
- `bash scripts/verify.sh` → `Verification passed.`
- New Go unit tests in `core/internal/syntax/` pass, including the reuse/trap regression (400 highlights).
- New Swift tests (`TextPositionTests` round-trip, `SyntaxHighlightingTests`, `AppStateTests` tokens) pass.
- Existing IPC tests (`open_file_test.go`) still pass: Go file → `language:"go"` + tokens; `.txt` → plain text.
- `bash scripts/perf-gate.sh` → idle RSS ≤ 50 MB, 0 child processes, no orphan, workspace unchanged.
- Manual: opening a `.go` file in the app shows appearance-aware coloring; Cmd+Click definition still lands on the correct symbol.

## Manual UI Check (after build)

1. `bash scripts/build-app.sh` then open `dist/ArchSight.app` (or run via the dev command from `scripts/setup.sh`).
2. Open a folder containing Go files; open a `.go` file.
3. Confirm keywords, strings, comments, functions, types, numbers, operators are colored, and the palette adapts when you toggle macOS dark mode.
4. Cmd+Click a symbol → definition still navigates correctly (proves token coloring did not disturb offset mapping).
