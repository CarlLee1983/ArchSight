# ArchSight macOS App

This directory contains the native SwiftUI/AppKit shell.

The app layer stays focused on native presentation, read-only navigation, workspace browsing, tabs, split views, search UI, and explicit user-triggered symbol navigation.

Heavy filesystem scanning, search execution, syntax parsing, LSP process management, and protocol orchestration belong in `core/`.

## Features

The shell currently provides:

- **Workspace** — open one or more folders via the native picker or drag/drop; folders appear as a flattened, per-root collapsible collection in the Explorer sidebar.
- **Recent folders** — opened folders are remembered (most-recent-first) and reopen in one click from File ▸ Open Recent or the welcome screen shown when no workspace is open; backed by `ArchSightKit/RecentFoldersStore`.
- **Explorer sidebar** — activity bar toggles between Explorer and Search panels; an Open Files list, collapsible `FOLDERS` sections, and a Collapse Folders action.
- **Sidebar context menus** — right-click a root for Reveal in Finder / Copy Path / Remove Folder / Close All Folders; right-click any entry for Reveal in Finder / Copy Path / Copy Relative Path.
- **Reading** — read-only file viewing with Tree-sitter syntax highlighting (served by `core/`), a Markdown preview/source toggle, and reading preferences (theme, text size, line spacing).
- **Navigation** — Quick Open fuzzy file finder, native Find-in-file bar, and Back/Forward history.
- **Editing surface** — horizontal tabs, a two-pane split view for side-by-side comparison, and a references panel for LSP-backed navigation.
- **Keyboard hints** — a `⌘/` cheat sheet overlay (Help ▸ Keyboard Shortcuts) plus shortcut-annotated toolbar tooltips, all sourced from a single `ShortcutCatalog`.

The UI does not scan files, run search, parse syntax, or manage LSP in the UI process.

## Keyboard Shortcuts

Sourced from `ArchSightKit/ShortcutCatalog.swift`, the single display catalog behind
the cheat sheet (`⌘/`) and toolbar tooltips. The cheat sheet groups these the same way:

| Category | Action | Shortcut |
|---|---|---|
| Navigation | New Window | `⌘N` |
| Navigation | Open Folder | `⌘O` |
| Navigation | Quick Open | `⌘P` |
| Navigation | Find in File | `⌘F` |
| Navigation | Back | `⌘[` |
| Navigation | Forward | `⌘]` |
| View | Toggle Sidebar | `⌘B` |
| View | Show Explorer | `⌘⇧E` |
| View | Show Search | `⌘⇧F` |
| View | Split Editor | `⌘\` |
| View | Collapse Folders | `⌥⌘0` |
| View | Increase Text Size | `⌘=` |
| View | Decrease Text Size | `⌘-` |
| Tabs | Go to Tab 1–9 | `⌘1`–`⌘9` |
| Tabs | Previous Tab | `⌘⇧[` |
| Tabs | Next Tab | `⌘⇧]` |
| Tabs | Close Tab / Window | `⌘W` |
| Help | Keyboard Shortcuts | `⌘/` |

The actual `keyboardShortcut` bindings live in the App target (mostly
`WorkspaceCommands.swift` and `ContentView.swift`); `Find in File` (`⌘F`) is the
AppKit native find bar and `New Window` (`⌘N`) is the `WindowGroup` default. A unit
test (`ShortcutCatalogTests`) keeps the catalog free of duplicate ids and bindings so
the on-screen hints stay consistent.

## Swift Package

The first app shell is a Swift Package:

- `ArchSightKit`: testable app state, IPC envelope models, Unix Domain Socket transport, core client, and core process supervision.
- `ArchSightApp`: SwiftUI executable target for the native shell.

Run local verification from this directory:

```sh
swift test
swift build
```

`ArchSightKit` carries the testable plumbing: the IPC envelope models, the Unix Domain Socket transport, the core client, and `CoreProcessSupervisor`/`CoreSession` for launching and owning the app-side connect/disconnect lifecycle. The launch plan passes `--socket` to `archsight-core` and talks `health` and workspace requests over newline-delimited JSON. See the Features section above for the user-facing surface.

## Core Binary Resolution

`CoreBinaryLocator.resolve` finds the `archsight-core` executable through an
`ARCHSIGHT_CORE_PATH` override, then a binary bundled at
`Contents/Resources/bin/archsight-core`, then one beside the running app
executable. `ARCHSIGHT_SOCKET_DIR` overrides the socket directory (default
`/tmp`). When nothing resolves, the shell runs a no-core fallback that lists
chosen roots without tree/file/search/navigation. See `docs/packaging.md` and
`scripts/build-app.sh`.
