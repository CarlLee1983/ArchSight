# Packaging and Developer Setup

This document covers how to build and run ArchSight locally, how the shipped app
bundle locates its helper binaries, and how missing optional tools degrade.

## Required toolchain

| Tool | Purpose | Install |
| --- | --- | --- |
| Xcode 15+ / Swift 6 | Build and run the macOS shell | App Store, then `xcode-select --install` |
| Go 1.25+ | Build the `archsight-core` service | `brew install go` |
| ripgrep (`rg`) | Full-text search backend | `brew install ripgrep` |

Run the setup helper to check the toolchain and build the core binary:

```sh
scripts/setup.sh            # report-only: shows what is present/missing
scripts/setup.sh --install  # install required + recommended tools via Homebrew
```

`setup.sh` is safe to run repeatedly. In report mode it never installs anything;
it builds `dist/bin/archsight-core` and prints the exact `swift run` command for
development.

## Optional language servers (lazy, never required at load)

Navigation servers are discovered with `exec.LookPath` and started only on a
`definition` or `references` request. When a server is absent, navigation for
that language returns a structured `unsupported_language` error and nothing else
breaks — workspace browse, file open, search, and syntax all keep working.

| Language | Server | Install |
| --- | --- | --- |
| Go | `gopls` | `brew install gopls` |
| TypeScript | `typescript-language-server` | `npm i -g typescript-language-server typescript` |
| Swift | `sourcekit-lsp` | Ships with Xcode |

## Tree-sitter grammars

Phase 4 ships a thin in-memory syntax adapter (Go, Swift, TypeScript, Markdown)
that keeps the IPC token schema stable. No Tree-sitter grammar binaries are
vendored yet; when grammars are bundled they belong under `third_party/` with
their licenses recorded in `third_party/README.md`, and they replace the adapter
without changing the macOS client contract.

## Run from source (development)

```sh
scripts/setup.sh
ARCHSIGHT_CORE_PATH="$PWD/dist/bin/archsight-core" \
  swift run --package-path apps/macos ArchSight
```

The shell launches and supervises the core, connects over a Unix Domain Socket,
and shuts the core down on exit.

## App bundle (distribution)

```sh
scripts/build-app.sh   # produces dist/ArchSight.app
open dist/ArchSight.app
```

The bundle is self-contained so it runs with no environment configuration:

```text
dist/ArchSight.app/Contents/
  Info.plist
  MacOS/ArchSight                # SwiftUI shell
  Resources/bin/archsight-core   # Go core service
  Resources/bin/rg               # bundled ripgrep
```

## Distribution via Homebrew cask

ArchSight ships as a Homebrew cask, not a formula. `scripts/release.sh` builds
the bundle, zips it with `ditto` (which preserves the bundle layout, symlinks,
extended attributes, and code signature), computes the SHA-256, and patches
`Casks/archsight.rb` with the new `version` and `sha256`:

```sh
scripts/release.sh             # build + zip + sha256 + patch the cask
scripts/release.sh --no-build  # reuse an existing dist/ArchSight.app
```

It then prints the manual publish steps: create a GitHub Release tagged
`v<version>` with the zip attached, and push the patched cask to a personal tap.

Two constraints drive this layout:

- **The cask must live in your own tap** (e.g. `CarlLee1983/homebrew-tap`). The
  official `homebrew/cask` repository does not accept apps that are not
  Developer ID signed and notarized.
- **The bundle is currently ad-hoc signed and not notarized.** Modern Homebrew
  *adds* the `com.apple.quarantine` attribute on cask installs and has **removed
  the `--no-quarantine` flag**, so Gatekeeper blocks the first launch. Users
  clear the flag once after install (the cask `caveats` spell this out):
  `xattr -dr com.apple.quarantine /Applications/ArchSight.app` — or open it once
  via right-click > Open. Notarizing the bundle (requires a paid Apple Developer
  Program membership) removes this step and is the prerequisite for ever
  submitting to `homebrew/cask`.

## Binary resolution and development fallbacks

Both the shell and the core resolve their helper binaries in the same order:
explicit override, bundled binary, then a development fallback. This lets the
packaged app run unconfigured while source builds use an override.

### Core executable (resolved by the shell)

`CoreBinaryLocator.resolve` (`apps/macos/.../CoreBinaryLocator.swift`):

1. `ARCHSIGHT_CORE_PATH` environment override.
2. `Bundle resourceURL/bin/archsight-core` (the shipped bundle).
3. `archsight-core` next to the running app executable.

If none resolve, the shell runs in a no-core fallback: chosen roots are listed
without tree, file, search, or navigation.

### ripgrep (resolved by the core)

`search.ResolveRipgrepPath` (`core/internal/search/resolve.go`):

1. `ARCHSIGHT_RG_PATH` environment override.
2. `rg` next to the running core executable (the shipped bundle).
3. bare `rg`, resolved from `PATH` at run time (development default).

### Socket location

`ARCHSIGHT_SOCKET_DIR` overrides the directory for the Unix Domain Socket
(`archsight-core.sock`); it defaults to `/tmp`.

## Verification

```sh
scripts/verify.sh
```

Checks project structure and Phase docs, reports toolchain presence, then runs
`go test ./core/...`, a core build, and `swift test` + `swift build` for the
macOS package.
