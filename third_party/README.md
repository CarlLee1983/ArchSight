# Third-Party Components

This directory documents bundled or vendored third-party binaries, grammars, and
licenses.

No third-party source is vendored into the repository. `scripts/build-app.sh`
copies binaries into the app bundle at build time; this file records where they
come from and their licenses.

## ripgrep (`rg`)

- **Used for**: full-text workspace search (`core/internal/search`).
- **Packaging**: `scripts/build-app.sh` copies the `rg` found on the build
  machine's `PATH` into `ArchSight.app/Contents/Resources/bin/rg`.
- **Runtime resolution**: `ARCHSIGHT_RG_PATH` override → bundled `rg` beside the
  core binary → `rg` from `PATH` (development default). See
  `core/internal/search/resolve.go`.
- **License**: MIT OR Unlicense (BurntSushi/ripgrep). Record the exact source
  build and license text here when shipping a pinned binary.

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

## Language servers (optional)

- **Status**: never bundled. `gopls`, `typescript-language-server`, and
  `sourcekit-lsp` are discovered on `PATH` and started lazily only on a
  `definition`/`references` request.
- **Missing server**: navigation for that language returns
  `unsupported_language`; everything else keeps working. No license obligation
  because nothing is redistributed.
