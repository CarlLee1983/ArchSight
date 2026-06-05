#!/usr/bin/env bash
# Phase 9 performance and reliability gate.
#
# Builds archsight-core, then drives it against a large synthetic workspace with
# the archsight-perfgate harness to measure startup latency, scan time, idle
# resident memory against the 50MB target, child-process count, search
# cancellation, and orphan processes after shutdown — while proving the
# workspace is never written to.
#
# Usage:
#   scripts/perf-gate.sh [--strict] [--dirs N] [--files N] [--out report.json]
#
# Exits non-zero on correctness failures. With --strict it also fails when idle
# memory exceeds the budget.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v go >/dev/null 2>&1; then
  echo "perf-gate: go toolchain is required" >&2
  exit 1
fi
if ! command -v rg >/dev/null 2>&1; then
  echo "perf-gate: ripgrep (rg) is required" >&2
  exit 1
fi

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

CORE_BIN="$BUILD_DIR/archsight-core"
echo "perf-gate: building archsight-core ..."
go build -o "$CORE_BIN" ./core/cmd/archsight-core

echo "perf-gate: running performance gate ..."
go run ./core/cmd/archsight-perfgate --core "$CORE_BIN" "$@"
