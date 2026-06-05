# ArchSight IPC Protocol

## Transport

The macOS app and core communicate over a local Unix Domain Socket. The transport is local-only and should not bind TCP ports.

Messages are newline-delimited JSON so the client and core can frame streaming events and responses without a heavyweight protocol dependency.

## Message Shape

All messages use request IDs so calls can be matched, streamed, and cancelled.

```json
{
  "id": "req_001",
  "method": "health",
  "params": {}
}
```

Responses use the same ID:

```json
{
  "id": "req_001",
  "ok": true,
  "result": {}
}
```

Errors are structured:

```json
{
  "id": "req_001",
  "ok": false,
  "error": {
    "code": "unsupported_method",
    "message": "Unsupported method: editFile"
  }
}
```

## Initial Methods

- `health`: confirms the core is running and reports version/process metadata.
- `openWorkspace`: opens one or more root folders and starts in-memory scanning.
- `listTree`: returns flattened workspace tree data.
- `openFile`: returns read-only file content and metadata.
- `search`: streams `ripgrep` results.
- `syntax`: returns syntax tokens for an opened file.
- `definition`: performs lazy LSP definition lookup.
- `references`: performs lazy LSP references lookup.
- `cancel`: cancels a request by ID.

No edit, format, code action, completion, or diagnostics methods are part of the protocol.

## Workspace Snapshot Methods

`openWorkspace` starts an in-memory asynchronous scan and returns immediately:

```json
{
  "id": "req_open",
  "method": "openWorkspace",
  "params": {
    "roots": ["/Users/alex/Code/service-a", "/Users/alex/Code/service-b"]
  }
}
```

The result includes the snapshot ID and preserved root identities:

```json
{
  "id": "req_open",
  "ok": true,
  "result": {
    "workspaceId": "ws_1",
    "status": "scanning",
    "roots": [
      {"id": "root_1", "name": "service-a", "path": "/Users/alex/Code/service-a"}
    ]
  }
}
```

`listTree` returns the current snapshot state. Entries are flattened but keep `rootId` and `rootPath` so the UI can preserve source-folder identity.

```json
{
  "id": "req_tree",
  "method": "listTree",
  "params": {
    "workspaceId": "ws_1"
  }
}
```

During Phase 2, `cancel` accepts a workspace scan ID through `targetId` or `workspaceId`.

## Search Method

`search` runs `ripgrep` against the roots of a ready workspace snapshot:

```json
{
  "id": "req_search",
  "method": "search",
  "params": {
    "workspaceId": "ws_1",
    "pattern": "needle"
  }
}
```

The result shape is ready for streaming even while Phase 3 returns a final aggregate response:

```json
{
  "id": "req_search",
  "ok": true,
  "result": {
    "matches": [
      {
        "rootId": "root_1",
        "rootPath": "/Users/alex/Code/service-a",
        "path": "cmd/main.go",
        "line": 12,
        "column": 8,
        "preview": "fmt.Println(\"needle\")",
        "ranges": [{"start": 12, "end": 18}]
      }
    ]
  }
}
```

`search` requires a ready workspace. Invalid patterns return `invalid_pattern`. Active searches can be canceled with `cancel` using the search request ID as `targetId`.

## Streaming

Long-running requests may emit events before a final response:

```json
{
  "id": "req_010",
  "event": "search.match",
  "payload": {
    "rootId": "root_1",
    "path": "Sources/App.swift",
    "line": 42,
    "column": 7,
    "preview": "let socket = ...",
    "ranges": [{"start": 7, "end": 13}]
  }
}
```

The final message marks completion:

```json
{
  "id": "req_010",
  "ok": true,
  "result": {
    "complete": true
  }
}
```

## Cancellation

The UI cancels long-running work with:

```json
{
  "id": "req_cancel_010",
  "method": "cancel",
  "params": {
    "targetId": "req_010"
  }
}
```

The core must propagate cancellation to directory scans, `rg` child processes, syntax work where feasible, and pending LSP requests.

## Compatibility

Protocol changes should be documented here before implementation. Breaking changes require coordinated updates to the macOS client, core handlers, tests, and smoke scripts.
