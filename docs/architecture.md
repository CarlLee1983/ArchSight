# ArchSight Architecture

## Intent

ArchSight is a native macOS read-only source-code observation tool. The architecture exists to keep the UI responsive and lightweight while delegating expensive filesystem, search, syntax, and LSP work to an isolated core process.

## Process Boundary

ArchSight is split into two primary processes:

- `apps/macos`: native SwiftUI/AppKit shell for presentation and user interaction.
- `core`: out-of-process service for filesystem snapshots, `ripgrep` search, Tree-sitter syntax parsing, IPC handling, and lazy LSP proxying.

The UI process should not scan large directory trees, launch language servers, execute `rg`, parse syntax trees, or manage long-running protocol state. Those responsibilities belong to the core process.

## UI Responsibilities

- Launch and supervise the core process.
- Open folders through native picker and drag/drop flows.
- Render flattened workspace collections.
- Render read-only file content, tabs, split views, search results, and navigation history.
- Send explicit user actions to the core over IPC.
- Show loading, error, empty, and cancellation states.

The UI must not expose editing, autocomplete, code actions, formatting, refactoring, or diagnostics.

## Core Responsibilities

- Maintain in-memory workspace snapshots.
- Preserve real root identities while presenting flattened collections.
- Run non-blocking directory scans with cancellation.
- Execute `ripgrep` for search and stream results.
- Parse syntax on demand through Tree-sitter.
- Proxy only definition and references LSP requests.
- Start language servers lazily and stop idle servers after 5 minutes.
- Avoid persistent project caches or repository metadata writes.

## Data Lifetime

Workspace state is in memory. ArchSight must not write cache databases, indexes, or project metadata into user repositories unless a future product decision explicitly changes that rule.

## Performance Posture

Performance is a product requirement, not a later optimization. The implementation should preserve:

- Native macOS rendering and scrolling.
- No language-server startup during workspace load.
- No background linting or indexing.
- Static memory as close as feasible to the target `M <= 50MB`.
- Clean shutdown without orphan core, `rg`, or LSP child processes.
