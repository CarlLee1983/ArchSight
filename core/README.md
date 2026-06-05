# ArchSight Core

This directory will contain the out-of-process core service.

The conservative default implementation language is Go because the core needs a single-binary deployment shape, clear process supervision, filesystem traversal, Unix Domain Socket IPC, child-process control for `rg`, and lazy LSP lifecycle management.

The core must not introduce editor behavior. It exposes read-only workspace, file, search, syntax, definition, and references capabilities to the macOS app.

## Phase 1 Service

The initial core service is a Go Unix Domain Socket server at `core/cmd/archsight-core`.
It speaks newline-delimited JSON envelopes and currently implements:

- `health`: returns core version and process ID.

Unsupported methods return structured `unsupported_method` errors. Editing, completion, code action, formatting, and diagnostics methods are intentionally absent.

## Phase 2 Workspace Snapshots

The core now maintains asynchronous in-memory workspace snapshots. `openWorkspace` returns immediately with a workspace ID while scanning continues in the core process. `listTree` reads the current snapshot state, and `cancel` can stop an active workspace scan.

Snapshot entries are flattened for UI presentation, but every entry carries `rootId` and `rootPath` so multiple dragged-in folders keep their real filesystem identity. Scanning skips common heavy directories: `.git`, `node_modules`, `build`, `.next`, `DerivedData`, `vendor`, and `.cache`.

Workspace scanning does not write cache files, databases, indexes, or metadata into opened roots.

Run core verification from the repository root:

```sh
go test ./core/...
go build ./core/cmd/archsight-core
```
