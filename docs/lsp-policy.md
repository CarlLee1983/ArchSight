# ArchSight LSP Policy

## Scope

ArchSight uses LSP only for explicit read-only navigation:

- `textDocument/definition`
- `textDocument/references`

Language servers must not be used for autocomplete, diagnostics, code actions, formatting, refactoring, or write-time assistance.

## Activation

Language servers are lazy:

1. Opening a workspace does not start any language server.
2. Opening a file does not start any language server.
3. A server may start only when the user explicitly requests definition or references for a supported language.
4. Only the server required for that language/root should start.

## Initialization

The core should advertise minimal client capabilities. Where the protocol and server allow it, ArchSight should avoid enabling:

- `completionProvider`
- `codeActionProvider`
- `documentFormattingProvider`
- `documentRangeFormattingProvider`
- diagnostics and publish-diagnostics flows

Some servers may still send extra notifications. The core should ignore or drop unsupported editor-oriented messages instead of exposing them through ArchSight IPC.

## Lifecycle

The core owns LSP process lifecycle:

- Track last request time per language-server process.
- Stop idle language servers after 5 minutes without definition or references requests.
- Stop associated servers when their workspace roots close.
- Prefer graceful LSP shutdown and process exit.
- Force-terminate processes that do not exit promptly.

## Current Implementation Status

The initial core implementation establishes the lazy lifecycle boundary:

- `definition` and `references` are the only IPC navigation methods.
- Workspace open and file open do not start language-server processes.
- Server processes are keyed by workspace root and language, then reused.
- Idle and core shutdown paths stop active language-server processes.
- Unsupported editor-oriented methods remain outside the IPC surface.
- The LSP client uses minimal JSON-RPC stdio framing for `initialize`, `initialized`, `textDocument/didOpen`, `textDocument/definition`, and `textDocument/references`.
- Definition and references responses are converted from LSP file URI locations into ArchSight root/path/range locations.

More advanced LSP support remains intentionally out of scope unless it serves explicit read-only navigation.

## Verification

Tests should prove:

- Workspace load starts zero language-server processes.
- File open starts zero language-server processes.
- Definition or references starts only the needed server.
- Idle cleanup stops the server.
- Completion, code action, formatting, and diagnostics are not exposed through ArchSight IPC.
