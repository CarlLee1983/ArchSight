# ArchSight Core

This directory will contain the out-of-process core service.

The conservative default implementation language is Go because the core needs a single-binary deployment shape, clear process supervision, filesystem traversal, Unix Domain Socket IPC, child-process control for `rg`, and lazy LSP lifecycle management.

The core must not introduce editor behavior. It exposes read-only workspace, file, search, syntax, definition, and references capabilities to the macOS app.
