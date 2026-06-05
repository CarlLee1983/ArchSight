# Performance and Reliability Gate

This document covers the Phase 9 gate that validates ArchSight's product thesis:
a fast, low-memory, strictly read-only observation tool whose expensive helpers
(search, language servers) are lazy and leave no orphan processes behind.

## What the gate proves

| Claim | How it is checked |
| --- | --- |
| Low idle memory (`M <= 50MB`) | Measures the core process RSS after a large workspace scan |
| Fast startup | Times core launch until the first `health` response |
| Fast scan | Times `openWorkspace` until `listTree` reports `ready` |
| No LSP on load | Counts child processes after scan — must be zero |
| Search works at scale | Counts matches of a known token against the synthetic workspace |
| Search is cancelable | Issues a search and cancels it from a second connection |
| No orphan processes | Verifies the core and any children are gone after `SIGTERM` |
| Read-only | Hashes every workspace file before and after; the diff must be empty |

## Running the gate

```sh
scripts/perf-gate.sh                 # build core, run the gate with defaults
scripts/perf-gate.sh --strict        # also fail if idle memory exceeds 50MB
scripts/perf-gate.sh --dirs 400 --files 50   # larger synthetic workspace
scripts/perf-gate.sh --out perf.json # also write a JSON report
```

The script builds `archsight-core` into a temp directory and drives it with the
`archsight-perfgate` harness (`core/cmd/archsight-perfgate`). It requires `go`
and `rg` on `PATH`.

Correctness failures (no-LSP-on-load, search mismatch, leftover socket, orphan
processes, a modified workspace) exit non-zero. Exceeding the memory budget is a
warning unless `--strict` is passed.

## Sample evidence

A representative local run (Apple M4, 200 dirs × 25 files = 5,002 files):

```
== ArchSight Phase 9 Performance & Reliability Gate ==
Synthetic workspace : 5002 files in 200 dirs (5202 tree entries)
Startup latency     : 379 ms
Scan time           : 24 ms
Idle memory         : 12272 KB (12.0 MB) budget 51200 KB [PASS]
Child procs at idle : 0 [no-LSP-on-load PASS]
Search matches      : 5000 / 5000 [PASS]
Search cancellation : completed_before_cancel (64 ms after cancel) [best-effort, non-gating]
Socket removed      : PASS
No orphan processes : PASS (0 survivors)
Workspace read-only : PASS (no changes)
```

The orphan check launches the core as its own process-group leader and verifies
the group is empty after `SIGTERM` (via `ps -g`), so it catches children
reparented to launchd and is immune to pid reuse.

Idle memory sits well under the 50MB target and no language server starts during
workspace load.

## Syntax highlighting performance

Syntax highlighting parses on demand with a fresh Tree-sitter (wazero) instance
per opened file: the first Go file in a session pays a one-time Wasm compile
(~90 ms), subsequent files ~6–13 ms. Highlighting runs in-process (no child
process) and does not affect idle memory, which is measured before any file is
opened. (These figures are from manual benchmarks on Apple M4; the perf gate
does not open files, so it does not exercise highlighting.)

## A note on search cancellation

The gate's cancellation check is best-effort timing: on small synthetic
workspaces ripgrep often finishes before the cancel request lands, which the gate
honestly reports as `completed_before_cancel`. Deterministic proof that
cancellation terminates the child process and returns a structured
`context_canceled` error lives in the unit and integration tests
(`core/internal/search` and `core/internal/ipc`). To observe a live
`canceled` outcome from the gate, run it against a much larger workspace
(e.g. `--dirs 2000 --files 50`) so the search runs long enough to interrupt.

## Deterministic end-to-end smoke test

`core/internal/e2e` runs the full read-only flow against a real IPC server over a
Unix Domain Socket using a fake language server: open a synthetic workspace,
search it, open a file, request a definition (which lazily starts exactly one
server), then advance the clock and confirm the server idles out. It asserts no
server starts during workspace load and that the workspace is never modified.
This test runs as part of `go test ./core/...` and `scripts/verify.sh`.
