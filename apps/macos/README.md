# ArchSight macOS App

This directory contains the native SwiftUI/AppKit shell scaffold.

The app layer remains focused on native presentation, read-only navigation, workspace browsing, tabs, split views, search UI, and explicit user-triggered symbol navigation.

Heavy filesystem scanning, search execution, syntax parsing, LSP process management, and protocol orchestration belong in `core/`.

## Swift Package

The first app shell is a Swift Package:

- `ArchSightKit`: testable app state, IPC envelope models, Unix Domain Socket transport, core client, and core process supervision.
- `ArchSightApp`: SwiftUI executable target for the native shell.

Run local verification from this directory:

```sh
swift test
swift build
```

The shell currently provides a dense native split view, folder picker and drag/drop root collection, read-only tab state, a core launch plan that passes `--socket` to `archsight-core`, and a tested core client path for `health` over newline-delimited JSON through a Unix Domain Socket. `CoreSession` owns the app-side connect/disconnect lifecycle. The UI does not scan files, run search, parse syntax, or manage LSP in the UI process.

## Core Binary Resolution

`CoreBinaryLocator.resolve` finds the `archsight-core` executable through an
`ARCHSIGHT_CORE_PATH` override, then a binary bundled at
`Contents/Resources/bin/archsight-core`, then one beside the running app
executable. `ARCHSIGHT_SOCKET_DIR` overrides the socket directory (default
`/tmp`). When nothing resolves, the shell runs a no-core fallback that lists
chosen roots without tree/file/search/navigation. See `docs/packaging.md` and
`scripts/build-app.sh`.
