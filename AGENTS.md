# ArchSight Agent Instructions

This file governs the entire `/Users/carl/Dev/CMG/ArchSight` workspace.

## Project Intent

ArchSight is a lightweight native macOS source-code observation tool for senior engineers. It is optimized for read-only code review, navigation, search, and multi-service comparison without the memory, startup, indexing, and CPU costs of Electron-based IDEs.

The product philosophy is **Extraction over Invention**: use native macOS rendering for the shell, and delegate search and syntax work to proven high-performance tools such as `ripgrep` and Tree-sitter instead of rebuilding those capabilities.

## Non-Negotiable Product Boundaries

- Build a read-only observation cockpit, not an editor.
- Do not add autocomplete, code actions, write-time diagnostics, heavy linting, or background indexing unless the user explicitly changes the product direction.
- Keep static runtime memory as close as possible to the target `M <= 50MB`; treat regressions against this target as architecture issues.
- Prefer lazy, demand-triggered work over background processes.
- Avoid persistent disk caches or databases for workspace snapshots unless the user explicitly approves a scope change.

## Preferred Architecture

- Use a native macOS UI layer with SwiftUI and AppKit.
- Keep heavy IO, filesystem snapshotting, LSP proxying, and protocol handling outside the UI process.
- Prefer an out-of-process core with a compiled single-binary deployment shape. Go is the conservative default for the core unless the user explicitly chooses Bun or another runtime.
- Use Unix Domain Sockets for local frontend/core IPC unless a platform constraint proves otherwise.
- Use Tree-sitter for syntax parsing and highlighting.
- Use `ripgrep` (`rg`) for full-text search; prefer bundling or locating a known binary instead of replacing it with a slower custom implementation.

## Workspace Model

- Model workspaces as in-memory snapshots.
- Support multiple dragged-in project folders, microservices, or modules as flattened collections in one sidebar.
- Preserve each folder's real filesystem path and identity even when presenting a flattened collection.
- Use non-blocking scanning and incremental UI updates for large trees.
- Do not write project metadata into user repositories unless the user explicitly asks for it.

## LSP Proxy Rules

LSP support must remain narrow and lazy:

1. Do not start any language server during project load.
2. Start a language server only when the user requests symbol navigation, definition lookup, or references for an opened file.
3. During LSP initialization, disable or avoid advertising completion, code actions, and diagnostics where the server protocol allows it.
4. Keep only the capabilities needed for:
   - `textDocument/definition`
   - `textDocument/references`
5. Stop idle language-server processes after 5 minutes without LSP requests or when their associated tabs/workspaces close.
6. Prefer graceful shutdown first, but ensure runaway language-server processes are terminated.

## Implementation Guidance

- Keep diffs small and aligned with the read-only, low-memory product direction.
- Prefer deletion, native APIs, and proven tools over new abstractions or dependencies.
- Add dependencies only when they preserve the lightweight architecture and provide clear value.
- Keep UI behavior dense, fast, and utilitarian; this is an engineering tool, not a marketing site.
- Use responsive native UI patterns that support large file trees, split panes, tabs, and repeated navigation workflows.
- Keep the frontend and core boundaries explicit; do not mix filesystem scanning or protocol orchestration into UI views.
- Treat performance, startup time, memory, and process lifetime as first-class acceptance criteria.

## Suggested Repository Shape

When creating the initial project structure, keep Swift UI and core implementation clearly separated. A reasonable starting point is:

```text
apps/macos/      # SwiftUI/AppKit shell
core/            # out-of-process core service
core/search/     # ripgrep integration
core/syntax/     # Tree-sitter integration
core/lsp/        # lazy LSP proxy and process lifecycle
docs/            # product, architecture, and protocol notes
scripts/         # local setup and verification helpers
```

Adapt this shape to the actual build system once the project is scaffolded.

## Verification Expectations

Before claiming completion, run the smallest checks that prove the changed behavior:

- Swift/macOS UI changes: build or test the Xcode/Swift package target when available.
- Core changes: run unit tests plus targeted integration tests for filesystem, search, syntax, or LSP behavior.
- IPC changes: verify frontend/core protocol compatibility with a smoke test.
- Performance-sensitive changes: include at least a lightweight memory, startup, or process-lifetime check when feasible.
- If verification cannot run because the project is not scaffolded yet, state that clearly and validate the generated files structurally.

## Source Document

These instructions were generated from `initiation.md`, which defines ArchSight as a native macOS, read-only, low-memory code observation tool built around SwiftUI/AppKit, an out-of-process core, Tree-sitter, `ripgrep`, Unix Domain Sockets, in-memory workspace snapshots, and lazy LSP activation.
