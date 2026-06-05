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

- **Status**: not yet vendored. Phase 4 uses a thin in-memory syntax adapter
  (`core/internal/syntax`) that keeps the IPC token schema stable.
- **When bundled**: place grammar binaries here and record the Tree-sitter
  runtime license (MIT) plus each grammar's license. The adapter boundary stays
  stable so grammars replace it without changing the macOS client contract.

## Language servers (optional)

- **Status**: never bundled. `gopls`, `typescript-language-server`, and
  `sourcekit-lsp` are discovered on `PATH` and started lazily only on a
  `definition`/`references` request.
- **Missing server**: navigation for that language returns
  `unsupported_language`; everything else keeps working. No license obligation
  because nothing is redistributed.
