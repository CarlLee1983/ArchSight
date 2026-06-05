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

section "Toolchain"
check_tool "go" "Install Go before Phase 1 core work."
check_tool "swift" "Install Xcode or Swift toolchain before macOS app work."
check_tool "xcodebuild" "Install Xcode before macOS app build verification."
check_tool "rg" "Install ripgrep or provide bundled rg before search work."

if [[ "$missing" -eq 0 ]]; then
  printf '\nPhase 0 verification passed.\n'
  exit 0
fi

printf '\nPhase 0 verification completed with missing prerequisites listed above.\n'
exit 1
