# ArchSight

A native macOS, read-only source-code observation tool for senior engineers.
ArchSight opens one or more local code folders, browses a fast flattened
workspace tree, views files with syntax highlighting, searches with `ripgrep`,
and offers narrow symbol navigation through lazy LSP activation — without the
memory, startup, and indexing cost of an Electron IDE.

It is an observation cockpit, not an editor: no editing, autocomplete, code
actions, write-time diagnostics, or background linting.

## Architecture

- **macOS shell** (`apps/macos`) — SwiftUI/AppKit, native rendering, read-only
  navigation. Does no filesystem scanning, search, syntax, or LSP work itself.
- **Core service** (`core`) — a single Go binary (`archsight-core`) speaking
  newline-delimited JSON over a Unix Domain Socket. Owns workspace snapshots,
  `ripgrep` search, the syntax adapter, and lazy LSP lifecycle.

See `docs/architecture.md`, `docs/ipc-protocol.md`, and `docs/lsp-policy.md`.

## Quickstart

```sh
# 1. Check tools and build the core binary (safe to re-run)
scripts/setup.sh            # add --install to install missing tools via Homebrew

# 2. Run the app from source
ARCHSIGHT_CORE_PATH="$PWD/dist/bin/archsight-core" \
  swift run --package-path apps/macos ArchSight
```

Required: Xcode 15+/Swift 6, Go 1.25+, ripgrep. Optional language servers
(`gopls`, `typescript-language-server`, `sourcekit-lsp`) enable navigation and
degrade gracefully when absent. Full details in `docs/packaging.md`.

## Build a distributable app bundle

```sh
scripts/build-app.sh   # produces a self-contained dist/ArchSight.app
open dist/ArchSight.app
```

The bundle ships `archsight-core` and `rg` under `Contents/Resources/bin`, so it
runs with no environment configuration.

## Verify

```sh
scripts/verify.sh   # structure + docs + toolchain + go test + swift test
```

## Repository layout

```text
apps/macos/   SwiftUI shell (ArchSightApp) + testable kit (ArchSightKit)
core/         Go core service and internal packages
docs/         architecture, ipc-protocol, lsp-policy, packaging
scripts/      setup.sh, build-app.sh, verify.sh
third_party/  bundled-binary and license notes
```
