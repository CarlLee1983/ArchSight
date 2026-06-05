# ArchSight Complete Work Plan

Date: 2026-06-05

## Requirements Summary

ArchSight is a native macOS, read-only source-code observation tool for senior engineers. The MVP must prove the core product claim: engineers can open one or more local code folders, browse a fast flattened workspace tree, view files with syntax highlighting, search with `ripgrep`, and invoke narrow symbol navigation through lazy LSP activation without turning the app into a heavyweight IDE.

The current repository contains:

- `initiation.md`: product initiation source document.
- `AGENTS.md`: generated workspace guidance derived from `initiation.md`.
- No application scaffold or Git repository yet.

## Acceptance Criteria

- The project has a clear monorepo structure separating macOS UI and core service boundaries.
- The macOS app can launch and open one or more folders.
- Workspace discovery is in-memory and does not write caches or metadata into user repositories.
- Search is powered by `ripgrep`, with cancellation and result streaming.
- Syntax highlighting is powered by Tree-sitter or a thin adapter prepared for Tree-sitter.
- LSP servers are not launched on project load; they start only for definition or references requests.
- Idle LSP processes are terminated after 5 minutes without requests.
- The app remains read-only: no editing, autocomplete, code actions, publish diagnostics, or background linting.
- Verification includes build checks, core unit tests, IPC smoke tests, and at least one lightweight memory/process-lifetime check.

## Architecture Decision Record

### Decision

Build ArchSight as a native SwiftUI/AppKit macOS shell plus an out-of-process core service connected through a Unix Domain Socket. Use Go as the default core implementation language until the user explicitly chooses Bun or another runtime.

### Drivers

- Low memory and startup overhead.
- Native macOS interaction quality.
- Strict read-only product boundary.
- Fast file discovery and search over large multi-service workspaces.
- Ability to manage LSP processes independently from the UI.

### Alternatives Considered

- **All-Swift monolith**: simpler packaging, but risks mixing UI and heavy IO/process lifecycle concerns.
- **Electron or Tauri shell**: faster cross-platform scaffolding, but conflicts with the macOS-native and low-memory product premise.
- **Bun core**: viable for fast prototyping, but a Go core is more conservative for single-binary process management, filesystem scanning, and Unix socket services.

### Why Chosen

The native shell plus Go core preserves the strongest constraints from `initiation.md`: low memory, process isolation, native UI performance, and controlled lifecycle management for expensive tools.

### Consequences

- The project needs explicit IPC schemas and compatibility tests.
- Packaging must include or locate `rg`, Tree-sitter grammars, and optional language servers.
- Some Swift/Go integration work is required early so boundaries do not drift.

## Proposed Repository Structure

```text
apps/
  macos/
    ArchSight.xcodeproj or Package.swift
    Sources/ArchSightApp/
    Tests/ArchSightAppTests/
core/
  cmd/archsight-core/
  internal/workspace/
  internal/search/
  internal/syntax/
  internal/lsp/
  internal/ipc/
  testdata/
docs/
  architecture.md
  ipc-protocol.md
  lsp-policy.md
scripts/
  verify.sh
  smoke-ipc.sh
third_party/
  README.md
```

## Implementation Phases

### Phase 0: Repository Baseline

Create the project skeleton and source-of-truth docs.

Tasks:

- Initialize Git if the user wants version control for this directory.
- Add `docs/architecture.md` documenting the UI/core boundary.
- Add `docs/ipc-protocol.md` defining request/response envelopes, streaming events, error shape, and cancellation.
- Add `docs/lsp-policy.md` documenting lazy activation, disabled capabilities, and idle shutdown behavior.
- Add `scripts/verify.sh` as the single local verification entry point.

Acceptance criteria:

- Directory structure exists.
- Docs match the constraints in `AGENTS.md`.
- `scripts/verify.sh` runs and reports missing toolchain items clearly instead of failing obscurely.

### Phase 1: Core Service Foundation

Create a Go core process that exposes local IPC primitives and basic health checks.

Tasks:

- Scaffold `core/cmd/archsight-core`.
- Implement Unix Domain Socket server startup and cleanup.
- Define IPC envelopes for `health`, `openWorkspace`, `listTree`, `search`, `openFile`, `definition`, `references`, and `cancel`.
- Add structured logging with process IDs and request IDs.
- Add unit tests for IPC envelope parsing and error responses.

Acceptance criteria:

- Core starts, accepts a `health` request, and exits cleanly.
- Socket path cleanup works after normal shutdown.
- Tests cover valid requests, malformed requests, and unsupported methods.

### Phase 2: Workspace Snapshot

Implement in-memory multi-folder workspace snapshots.

Implementation status:

- Added an asynchronous Go workspace manager under `core/internal/workspace`.
- Added IPC support for `openWorkspace`, `listTree`, and workspace-scan cancellation.
- Snapshot entries are flattened while preserving `rootId` and `rootPath`.
- Scans skip `.git`, `node_modules`, `build`, `.next`, `DerivedData`, `vendor`, and `.cache`.
- Tests cover multi-root snapshots, ignored directories, no repository metadata writes, cancellation, and IPC open/list behavior.

Tasks:

- Add workspace model preserving source folder identity and real paths.
- Implement non-blocking directory scan with ignore rules for common heavy folders such as `.git`, `node_modules`, `build`, `.next`, `DerivedData`, and vendor caches.
- Support flattened collections in the returned tree.
- Add cancellation for long scans.
- Add tests using synthetic multi-service fixtures.

Acceptance criteria:

- Opening multiple roots returns a single flattened collection without losing root identity.
- No cache/database files are written into opened roots.
- Scan cancellation stops work promptly.
- Large ignored directories are skipped.

### Phase 3: Search Through Ripgrep

Integrate `ripgrep` as the full-text search backend.

Implementation status:

- Added a `ripgrep --json` search backend under `core/internal/search`.
- Search results include `rootId`, `rootPath`, relative path, line, column, preview text, and match ranges.
- IPC `search` runs against ready workspace snapshots and maps invalid regex patterns to structured `invalid_pattern` errors.
- Active search requests can be canceled through `cancel targetId=<search request id>`.
- Tests cover command construction, ignored directories, invalid patterns, cancellation, root identity, and IPC search behavior.

Tasks:

- Detect bundled `rg` first, then system `rg` as a development fallback.
- Stream search results through IPC.
- Include path, line, column, preview text, root identity, and match ranges.
- Implement cancellation by request ID.
- Add tests around command construction and result parsing.

Acceptance criteria:

- Search results stream incrementally.
- Cancelling a search terminates the child process.
- Search respects opened roots and ignore rules.
- Invalid patterns return structured errors.

### Phase 4: Syntax Pipeline

Add syntax highlighting support without introducing heavy editor behavior.

Implementation status:

- Added IPC `openFile` for ready workspace snapshots with root identity, relative path validation, and read-only file content.
- Added a stable syntax token response format under `core/internal/syntax`.
- Added an initial thin syntax adapter for Go, Swift, TypeScript, and Markdown language detection, with keyword tokens for supported code files.
- Unsupported languages degrade to plain text with an empty token list.
- Tests cover supported file content/tokens, unsupported plain-text fallback, path traversal rejection, and ignored files outside the snapshot.

Tasks:

- Define syntax token response format.
- Integrate Tree-sitter for a small initial language set, such as Swift, Go, TypeScript, and Markdown, or create the adapter with one language first if grammar packaging needs staging.
- Parse opened file content on demand.
- Cache only in memory and invalidate when files are reopened or changed on disk.
- Add tests for token ranges and parser errors.

Acceptance criteria:

- Opening a supported file returns content plus syntax tokens.
- Unsupported languages degrade to plain text.
- Parser failures do not crash the core.
- No text editing APIs are introduced.

### Phase 5: Lazy LSP Proxy

Implement narrow definition and references support.

Implementation status:

- Added a narrow LSP lifecycle manager under `core/internal/lsp`.
- Added IPC support for `definition` and `references` with ready-workspace, root identity, relative path, snapshot membership, language detection, and cancellation-aware forwarding.
- Workspace load and `openFile` do not invoke LSP navigation.
- Language-server processes start lazily per root/language, are reused, and are stopped on idle cleanup or core shutdown.
- Completion, code action, diagnostics, and formatting remain unsupported IPC methods.
- Added minimal JSON-RPC stdio framing for `initialize`, `initialized`, `textDocument/didOpen`, `textDocument/definition`, and `textDocument/references`.
- Definition and references responses are parsed from LSP file URI locations into ArchSight root/path/range locations.

Tasks:

- Add language-server registry for initial servers such as `gopls` and TypeScript language server.
- Start servers only on `definition` or `references`.
- Initialize with minimal client capabilities and avoid completion, code actions, and diagnostics.
- Track last request timestamp per LSP process.
- Shut down idle servers after 5 minutes.
- Add integration tests with fake LSP server fixtures.

Acceptance criteria:

- Project load does not start any language server.
- First definition or references request starts only the needed server.
- Completion, code action, and diagnostics paths are not exposed through ArchSight IPC.
- Idle cleanup terminates the server.

### Phase 6: macOS App Shell

Build the first native UI experience.

Implementation status:

- Added a Swift Package under `apps/macos`.
- Added `ArchSightKit` for IPC envelope models, read-only workspace view state, and core process supervision.
- Added `ArchSightApp` SwiftUI executable target with a native three-column shell, folder picker, drag/drop root intake, flattened-tree sidebar, read-only file pane, and a working search field.
- Added a Swift core client and Unix Domain Socket transport for newline-delimited JSON IPC, with a generic request envelope that carries typed params (`openWorkspace`, `listTree`, `openFile`, `search`).
- Added `CoreClient` methods for `openWorkspace`, `listTree`, `openFile`, and `search` behind a `CoreServicing` protocol, with tested request encoding and structured-error decoding.
- Added `WorkspaceController` to orchestrate the read-only workflow: open a snapshot, poll `listTree` until the scan settles (with timeout and failed-status surfacing), load files as read-only tabs, and run searches.
- Added `CoreSession` to own app-side core start, health check, connection status, failure cleanup, and disconnect lifecycle, plus a Sendable `CoreServiceEndpoint` so blocking IPC runs off the main thread while only value types cross the boundary.
- Wired the SwiftUI shell to connect through `ARCHSIGHT_CORE_PATH`: adding folders reopens the workspace via the core, the sidebar renders the flattened tree grouped by root, tree rows and search matches open files read-only, and the search field runs ripgrep-backed search; a no-core fallback shows chosen roots without tree/file/search.
- The app shell keeps filesystem scanning, search execution, syntax parsing, and LSP orchestration outside the UI process.
- Added Swift package build/test coverage (29 tests) and included it in `scripts/verify.sh`; verified the full `openWorkspace → listTree → openFile → search` flow end-to-end against the real Go core with no orphan process after shutdown.

Tasks:

- Scaffold SwiftUI/AppKit app under `apps/macos`.
- Add folder picker and drag/drop folder opening.
- Launch and supervise the core process.
- Connect to the Unix Domain Socket.
- Render workspace sidebar, file tabs, read-only code viewer, and search panel.
- Add basic error and loading states.

Acceptance criteria:

- App launches locally.
- User can open multiple folders.
- Sidebar shows flattened workspace tree.
- User can open files read-only.
- Search panel streams results and opens selected matches.
- Core process exits when the app exits.

### Phase 7: Navigation UX

Complete the observation workflow for code review.

Implementation status:

- Added an AppKit-backed read-only `CodeTextView` (NSTextView in NSScrollView) with monospaced rendering, no editing affordances, Cmd+Click to request a definition, and a context menu exposing `Go to Definition` and `Find References` as explicit user actions.
- Added `CoreClient.definition`/`references` behind `CoreServicing` and `WorkspaceController.definition`/`references` returning `[Location]`, with `Location`/`NavigationResult`/`NavigationParams` IPC models.
- Added a tested `TextPosition.lineColumn(forUTF16Offset:in:)` helper so AppKit click offsets map to the 1-based line/column the core expects.
- Added tab management on `WorkspaceViewState` (`closeTab` with neighbor selection, `selectNextTab`/`selectPreviousTab`) and a `NavigationHistory` value type for back/forward with forward-branch truncation.
- Wired the shell with a split-pane (`HSplitView`) comparison view, per-tab close buttons (no edit affordances), a dismissable references panel that opens and scrolls to each location, keyboard-navigable tree and search lists (arrow keys plus Return to open), and keyboard shortcuts for back/forward (Cmd+[ / Cmd+]), close tab (Cmd+W), and next/previous tab (Cmd+Shift+] / Cmd+Shift+[).
- Definition jumps and reference selections open the target file read-only and scroll to the symbol; navigation never exposes editing, formatting, refactoring, or diagnostics.
- Added Swift package tests (52 total) and verified the definition/references request path end-to-end against the real core (correct param parsing, `unsupported_language` without an installed server, `invalid_params` on bad positions, no orphan process); the successful-server path stays covered by the Phase 5 fake-LSP Go tests.

Tasks:

- Add split-pane layout for comparing files.
- Add tab management without edit affordances.
- Add `Cmd+Click` symbol definition request.
- Add references panel.
- Add keyboard navigation for tree, search results, tabs, and back/forward history.

Acceptance criteria:

- Code review flow works without requiring mouse-only interaction.
- Definition and references requests are visible as intentional user actions.
- No UI suggests editing, formatting, refactoring, or diagnostics.

### Phase 8: Packaging and Developer Setup

Make the project repeatable for local development.

Implementation status:

- Added `scripts/setup.sh` as a safe, report-by-default developer bootstrap: it checks the required toolchain (Go, ripgrep, Xcode/Swift), reports optional language servers (`gopls`, `typescript-language-server`, `sourcekit-lsp`) as never-required, builds `dist/bin/archsight-core`, and prints the exact dev run command. `--install` installs required/recommended tools via Homebrew.
- Added `scripts/build-app.sh` to assemble a self-contained `dist/ArchSight.app` with the Swift shell in `Contents/MacOS`, and `archsight-core` plus `rg` under `Contents/Resources/bin`, so the shipped app runs with no environment configuration. Verified end-to-end: the bundle builds and all three binaries are arm64 Mach-O executables in the expected layout.
- Added core ripgrep resolution `search.ResolveRipgrepPath` (override `ARCHSIGHT_RG_PATH` → bundled `rg` beside the core binary → bare `rg` from `PATH`), wired through `archsight-core` main, with unit tests for each branch.
- Added Swift `CoreBinaryLocator.resolve` (override `ARCHSIGHT_CORE_PATH` → bundled `Resources/bin/archsight-core` → sibling of the app executable) and routed `CoreSessionFactory.fromEnvironment` through it so the packaged app needs no env var, with unit tests for each branch. A missing core keeps the existing no-core fallback.
- Documented setup, optional LSP graceful degradation, Tree-sitter grammar status, the bundle layout, and the full binary-resolution precedence in `docs/packaging.md`; added a root `README.md` quickstart; recorded ripgrep/Tree-sitter/LSP packaging decisions in `third_party/README.md`; and added Phase 8 notes to `core/README.md` and `apps/macos/README.md`.
- Extended `scripts/verify.sh` with Phase 8 artifact checks (`README.md`, `docs/packaging.md`, `scripts/setup.sh`, `scripts/build-app.sh`).

Tasks:

- Add setup script for required tools.
- Document Xcode, Go, `rg`, Tree-sitter grammar, and optional LSP dependencies.
- Add app bundle strategy for `archsight-core` and `rg`.
- Add development fallback paths for unbundled tools.

Acceptance criteria:

- A new developer can build and run from documented steps.
- Missing optional LSPs degrade gracefully.
- Required binaries are either bundled or clearly detected.

### Phase 9: Performance and Reliability Gate

Validate the product thesis.

Implementation status:

- Added `core/internal/fixtures` to generate a deterministic large synthetic workspace (parametrized `Dirs`/`FilesPerDir`, anchor `main.go`/`target.go`, one search needle per leaf file) plus a content `Manifest`/`DiffManifests` used to prove workspace operations never write into source roots. Unit tested.
- Added `core/internal/perf` with process-measurement helpers (`ProcessRSSKilobytes`, `DescendantPIDs`, `IsAlive`) and tested pure parsers for `ps`/`pgrep` output.
- Added `core/internal/e2e`, a deterministic end-to-end smoke test that drives a real IPC server over a Unix Domain Socket: `health → openWorkspace → listTree (until ready) → search → openFile → definition (via fake LSP) → idle-out`. It asserts no language server starts during workspace load, that the definition lazily starts exactly one server, that the server idles out after the timeout, and that the workspace manifest is unchanged.
- Added `core/cmd/archsight-perfgate`, a harness that launches the real `archsight-core` binary against a large synthetic workspace and measures startup latency, scan time, idle RSS against the `M <= 50MB` target, child-process count (no LSP on load), search match count, best-effort search cancellation, socket cleanup, orphan processes after `SIGTERM`, and read-only proof. It emits a human report and optional JSON, and exits non-zero on correctness failures (`--strict` also fails on memory over budget).
- Added `scripts/perf-gate.sh` to build the core and run the gate, and documented the gate, sample evidence, and the cancellation caveat in `docs/performance.md`.
- Extended `scripts/verify.sh` with Phase 9 artifact checks; the new packages run under `go test ./core/...`.
- Verified evidence on Apple M4 (5,002 files): startup 421 ms, scan 28 ms, idle memory 12.1 MB (under the 50 MB target), 0 child processes at idle, 5000/5000 search matches, socket removed, no orphan processes, workspace unchanged.

Tasks:

- Add a fixture or script to open a large synthetic workspace.
- Measure startup time, idle memory, core process count, and search cancellation behavior.
- Confirm no LSP process starts during workspace load.
- Add a smoke test that opens workspace, searches, opens file, requests definition through fake LSP, then idles out.

Acceptance criteria:

- Idle static memory is measured and tracked against the `M <= 50MB` target.
- No unexpected child processes remain after shutdown.
- Workspace load does not write files into opened roots.
- Verification evidence is captured in command output or docs.

## Test Plan

### Unit Tests

- IPC envelope parsing and error handling.
- Workspace tree modeling and root identity preservation.
- Ignore rule handling.
- Search result parsing.
- Syntax token range generation.
- LSP lifecycle state machine.

### Integration Tests

- Core health over Unix Domain Socket.
- Workspace open plus tree listing.
- Search streaming and cancellation.
- Fake LSP definition/references flow.
- Idle LSP cleanup.

### UI Smoke Tests

- Launch app.
- Open one or more folders.
- Browse sidebar.
- Open file in read-only viewer.
- Search and navigate to a result.
- Trigger definition request.

### Performance Checks

- Startup time.
- Idle memory.
- Scan time for large fixture.
- Child process count before and after LSP request.
- Search cancellation latency.

## Risks and Mitigations

- **Risk: SwiftUI code viewer performance is insufficient for large files.**
  Mitigation: use AppKit-backed text rendering or a custom tiled viewer if measurement shows frame drops.

- **Risk: Tree-sitter grammar packaging adds complexity.**
  Mitigation: start with one grammar and keep the adapter boundary stable before expanding language support.

- **Risk: LSP servers ignore reduced capability preferences.**
  Mitigation: keep ArchSight IPC narrow and drop unsupported notifications/results instead of exposing editor features.

- **Risk: Memory target is missed by default Swift/AppKit components.**
  Mitigation: measure early and avoid WebView/Electron-style embeddings.

- **Risk: Bundling `rg` and grammars affects distribution.**
  Mitigation: document licenses and maintain a `third_party/README.md`.

## Execution Order

1. Establish docs and repository skeleton.
2. Build core IPC health path.
3. Add workspace snapshot model.
4. Add ripgrep search.
5. Add read-only file open and syntax token API.
6. Add lazy LSP definition/references using fake-server tests first.
7. Build macOS shell around the stable core API.
8. Add code review UX features.
9. Package and run performance gates.

## Suggested Agent Staffing

- `architect`: review UI/core boundary, IPC protocol, and packaging decisions.
- `executor`: implement scaffold, core service, app shell, and feature slices.
- `test-engineer`: create fixtures, fake LSP server, and verification scripts.
- `verifier`: run final build, smoke, performance, and process-lifetime checks.
- `designer`: review dense macOS workflow, sidebar/search/tabs ergonomics, and read-only affordances.

For parallel delivery, use Team + Ultragoal:

- Ultragoal owns durable milestones and completion evidence.
- Team splits execution into core, macOS UI, tests, and docs lanes.
- Team shuts down only after build, tests, smoke checks, and performance evidence are reported back to the Ultragoal ledger.

## Launch Hints

From an OMX CLI/tmux runtime, reasonable follow-up commands would be:

```text
$ultragoal .omx/plans/archsight-complete-work-plan.md
$team .omx/plans/archsight-complete-work-plan.md
```

In this Codex App surface, continue by asking for a specific phase or by asking to start implementation; execution can proceed directly in this workspace without tmux-only OMX surfaces.

## Stop Condition

The complete work is done when ArchSight can be built locally, opens multiple code folders, provides read-only tree/file/search/syntax/navigation workflows, proves lazy LSP lifecycle behavior, exits without orphan processes, and has fresh verification evidence for build, tests, IPC smoke, and lightweight memory/process checks.
