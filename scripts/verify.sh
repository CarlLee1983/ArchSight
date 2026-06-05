#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
missing=0

section() {
  printf '\n== %s ==\n' "$1"
}

check_file() {
  local path="$1"
  if [[ -f "$ROOT_DIR/$path" ]]; then
    printf 'OK      %s\n' "$path"
  else
    printf 'MISSING %s\n' "$path"
    missing=1
  fi
}

check_dir() {
  local path="$1"
  if [[ -d "$ROOT_DIR/$path" ]]; then
    printf 'OK      %s/\n' "$path"
  else
    printf 'MISSING %s/\n' "$path"
    missing=1
  fi
}

check_tool() {
  local name="$1"
  local hint="$2"
  if command -v "$name" >/dev/null 2>&1; then
    printf 'OK      %-12s %s\n' "$name" "$(command -v "$name")"
  else
    printf 'MISSING %-12s %s\n' "$name" "$hint"
    missing=1
  fi
}

section "Project structure"
check_file "AGENTS.md"
check_file "initiation.md"
check_dir "apps/macos"
check_dir "core"
check_dir "docs"
check_dir "scripts"
check_dir "third_party"

section "Phase 0 documents"
check_file "docs/architecture.md"
check_file "docs/ipc-protocol.md"
check_file "docs/lsp-policy.md"
check_file "apps/macos/README.md"
check_file "core/README.md"
check_file "third_party/README.md"

section "Phase 8 packaging"
check_file "README.md"
check_file "docs/packaging.md"
check_file "scripts/setup.sh"
check_file "scripts/build-app.sh"

section "Phase 9 performance gate"
check_file "scripts/perf-gate.sh"
check_file "docs/performance.md"
check_file "core/cmd/archsight-perfgate/main.go"

section "Toolchain"
check_tool "go" "Install Go before Phase 1 core work."
check_tool "swift" "Install Xcode or Swift toolchain before macOS app work."
check_tool "xcodebuild" "Install Xcode before macOS app build verification."
check_tool "rg" "Install ripgrep or provide bundled rg before search work."

section "Core"
if command -v go >/dev/null 2>&1; then
  if (cd "$ROOT_DIR" && go test ./core/...); then
    printf 'OK      go test ./core/...\n'
  else
    printf 'FAILED  go test ./core/...\n'
    missing=1
  fi

  build_dir="$(mktemp -d)"
  trap 'rm -rf "$build_dir"' EXIT
  if (cd "$ROOT_DIR" && go build -o "$build_dir/archsight-core" ./core/cmd/archsight-core); then
    printf 'OK      go build ./core/cmd/archsight-core\n'
  else
    printf 'FAILED  go build ./core/cmd/archsight-core\n'
    missing=1
  fi
else
  printf 'SKIP    core tests/build because go is missing\n'
fi

section "macOS app"
if command -v swift >/dev/null 2>&1; then
  if [[ -f "$ROOT_DIR/apps/macos/Package.swift" ]]; then
    if (cd "$ROOT_DIR/apps/macos" && swift test); then
      printf 'OK      swift test apps/macos\n'
    else
      printf 'FAILED  swift test apps/macos\n'
      missing=1
    fi

    if (cd "$ROOT_DIR/apps/macos" && swift build); then
      printf 'OK      swift build apps/macos\n'
    else
      printf 'FAILED  swift build apps/macos\n'
      missing=1
    fi
  else
    printf 'SKIP    macOS Swift package because apps/macos/Package.swift is missing\n'
  fi
else
  printf 'SKIP    macOS app tests/build because swift is missing\n'
fi

if [[ "$missing" -eq 0 ]]; then
  printf '\nVerification passed.\n'
  exit 0
fi

printf '\nVerification completed with failures or missing prerequisites listed above.\n'
exit 1
