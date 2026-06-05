#!/usr/bin/env bash
#
# ArchSight developer setup.
#
# By default this script only *reports* what is installed and what is missing,
# so it is safe to run at any time. Pass --install to let it install the
# required tools through Homebrew. Optional language servers are never required;
# missing servers degrade gracefully to `unsupported_language` at run time.
#
# Usage:
#   scripts/setup.sh            # report-only
#   scripts/setup.sh --install  # install required + recommended tools via brew
#
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL=0
missing_required=0

for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    -h|--help)
      grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s (use --help)\n' "$arg" >&2
      exit 2
      ;;
  esac
done

section() { printf '\n== %s ==\n' "$1"; }

# brew_install <formula> — install through Homebrew when --install is set.
brew_install() {
  local formula="$1"
  if [[ "$INSTALL" -ne 1 ]]; then
    printf '        run with --install (or: brew install %s)\n' "$formula"
    return 1
  fi
  if ! command -v brew >/dev/null 2>&1; then
    printf '        Homebrew is required to install %s; see https://brew.sh\n' "$formula"
    return 1
  fi
  printf '        installing %s via Homebrew...\n' "$formula"
  brew install "$formula"
}

# require <command> <brew-formula> <hint>
require() {
  local cmd="$1" formula="$2" hint="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf 'OK      %-26s %s\n' "$cmd" "$(command -v "$cmd")"
    return 0
  fi
  printf 'MISSING %-26s %s\n' "$cmd" "$hint"
  if ! brew_install "$formula"; then
    missing_required=1
  fi
}

# recommend <command> <brew-formula> <hint> — optional, never fails the run.
recommend() {
  local cmd="$1" formula="$2" hint="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf 'OK      %-26s %s\n' "$cmd" "$(command -v "$cmd")"
    return 0
  fi
  printf 'OPTIONAL %-25s %s\n' "$cmd" "$hint"
  brew_install "$formula" || true
}

section "Required toolchain"
require "go" "go" "Install Go 1.25+ for the core service."
require "rg" "ripgrep" "Install ripgrep for full-text search."
if command -v xcodebuild >/dev/null 2>&1 || command -v swift >/dev/null 2>&1; then
  printf 'OK      %-26s %s\n' "swift/xcode" "$(command -v swift 2>/dev/null || command -v xcodebuild)"
else
  printf 'MISSING %-26s %s\n' "swift/xcode" "Install Xcode from the App Store, then run xcode-select --install."
  missing_required=1
fi

section "Optional language servers (lazy, never required at load)"
recommend "gopls" "gopls" "Go definitions/references. Without it, Go navigation returns unsupported_language."
recommend "typescript-language-server" "typescript-language-server" "TypeScript navigation. Pair with 'typescript'."
if command -v sourcekit-lsp >/dev/null 2>&1; then
  printf 'OK      %-26s %s\n' "sourcekit-lsp" "$(command -v sourcekit-lsp)"
else
  printf 'OPTIONAL %-25s %s\n' "sourcekit-lsp" "Ships with Xcode; run xcode-select --install to expose it."
fi

section "Build the core binary"
if command -v go >/dev/null 2>&1; then
  mkdir -p "$ROOT_DIR/dist/bin"
  if (cd "$ROOT_DIR" && go build -o "dist/bin/archsight-core" ./core/cmd/archsight-core); then
    printf 'OK      built dist/bin/archsight-core\n'
    printf '        run the app with: ARCHSIGHT_CORE_PATH="%s/dist/bin/archsight-core" swift run --package-path apps/macos ArchSight\n' "$ROOT_DIR"
  else
    printf 'FAILED  go build ./core/cmd/archsight-core\n'
    missing_required=1
  fi
else
  printf 'SKIP    core build because go is missing\n'
fi

if [[ "$missing_required" -eq 0 ]]; then
  printf '\nSetup ready. Next: scripts/verify.sh\n'
  exit 0
fi

printf '\nSetup incomplete: install the MISSING items above (or re-run with --install).\n'
exit 1
